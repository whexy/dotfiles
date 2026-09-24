"""`wechat login | logout | status | send | recv | ask`."""

import argparse
import html
import io
import json
import sys
import time
from pathlib import Path

import qrcode

from wechat_cli import media
from wechat_cli.api import NO_CONTEXT_RET, Client, Json, WechatError
from wechat_cli.messages import outbound, poll, text_item
from wechat_cli.state import (
    Account,
    forget,
    load_account,
    load_account_or_none,
    load_sync,
    save_account,
)

LOGIN_TIMEOUT = 480.0
MAX_QR_REFRESHES = 3
NO_CONTEXT_HELP = (
    "the bot can only send within 24 hours of the user's last message: "
    "message the bot from WeChat, then run `wechat recv` to pick up the conversation"
)
# Server timestamps may run slightly behind the local clock.
ASK_CLOCK_SKEW = 5.0


def show_qr(escaped_url: str) -> None:
    # The backend returns the URL HTML-escaped.
    url = html.unescape(escaped_url)
    code = qrcode.QRCode(border=1)
    code.add_data(url)
    buf = io.StringIO()
    code.print_ascii(out=buf, invert=True)
    print(buf.getvalue(), file=sys.stderr)
    print(f"Scan with WeChat, or open: {url}", file=sys.stderr)


def login(_: argparse.Namespace) -> None:
    previous = load_account_or_none()
    client = Client()
    known = [previous.token] if previous else []
    qr = client.fetch_qrcode(known)
    show_qr(qr["qrcode_img_content"])
    poller = Client()
    verify_code: str | None = None
    refreshes = 0
    deadline = time.monotonic() + LOGIN_TIMEOUT
    while time.monotonic() < deadline:
        status = poller.qrcode_status(qr["qrcode"], verify_code)
        match status.get("status"):
            case "scaned":
                verify_code = None
                print("Scanned; confirm on your phone.", file=sys.stderr)
            case "need_verifycode":
                prompt = (
                    "Wrong number, try again: "
                    if verify_code
                    else "Enter the number shown in WeChat: "
                )
                verify_code = input(prompt).strip()
                continue
            case "scaned_but_redirect" if status.get("redirect_host"):
                poller = Client(f"https://{status['redirect_host']}")
            case "expired" | "verify_code_blocked":
                refreshes += 1
                if refreshes > MAX_QR_REFRESHES:
                    raise WechatError("QR code expired too many times; try again later")
                verify_code = None
                print("QR code expired; here is a new one.", file=sys.stderr)
                qr = client.fetch_qrcode(known)
                show_qr(qr["qrcode_img_content"])
            case "binded_redirect":
                print("This WeChat is already bound to the saved bot.", file=sys.stderr)
                return
            case "confirmed":
                account = Account(
                    token=status["bot_token"],
                    bot_id=status["ilink_bot_id"],
                    user_id=status["ilink_user_id"],
                    base_url=status.get("baseurl") or client.base_url.rstrip("/"),
                )
                save_account(account)
                print(f"Logged in; messages go to {account.user_id}", file=sys.stderr)
                return
            case _:
                pass
        time.sleep(1)
    raise WechatError("timed out waiting for the QR code to be scanned")


def logout(_: argparse.Namespace) -> None:
    print("Removed saved credentials." if forget() else "Not logged in.", file=sys.stderr)


def status(args: argparse.Namespace) -> None:
    account = load_account_or_none()
    window = load_sync().send_window(account.user_id, time.time()) if account else None
    if args.json:
        info: Json = {"logged_in": account is not None}
        if account:
            info |= {
                "bot_id": account.bot_id,
                "user_id": account.user_id,
                "send_window_seconds": max(0, int(window)) if window is not None else 0,
            }
        print(json.dumps(info))
    elif account:
        print(f"Logged in as bot {account.bot_id}; default recipient {account.user_id}")
        if window is not None and window > 0:
            print(f"Can send for another {format_duration(window)}")
        else:
            print("Cannot send until the user messages the bot from WeChat")
    else:
        print("Not logged in; run `wechat login`")
    if account is None:
        sys.exit(1)


def format_duration(seconds: float) -> str:
    minutes = int(seconds // 60)
    return f"{minutes // 60}h{minutes % 60:02d}m"


def client_for(account: Account) -> Client:
    return Client(account.base_url, account.token)


def send_to(account: Account, to: str, text: str, files: list[Path], kind: str | None) -> list[str]:
    sync = load_sync()
    window = sync.send_window(to, time.time())
    if window is None:
        raise WechatError(NO_CONTEXT_HELP)
    if window <= 0:
        raise WechatError(
            f"the conversation expired {format_duration(-window)} ago; {NO_CONTEXT_HELP}"
        )
    context_token = sync.context_tokens[to]
    client = client_for(account)
    items: list[Json] = [text_item(text)] if text else []
    for path in files:
        if not path.is_file():
            raise WechatError(f"no such file: {path}")
        items.append(media.upload(client, path, to, media.kind_of(path, kind)))
    if not items:
        raise WechatError("nothing to send: give text, --file, or pipe text on stdin")
    ids: list[str] = []
    # The backend accepts exactly one item per message.
    for item in items:
        try:
            resp = client.send_message(outbound(to, item, context_token))
        except WechatError as error:
            if error.ret == NO_CONTEXT_RET:
                raise WechatError(f"{error}; {NO_CONTEXT_HELP}") from error
            raise
        ids.append(str(resp.get("message_id") or ""))
    return ids


def read_text(words: list[str]) -> str:
    if words == ["-"] or (not words and not sys.stdin.isatty()):
        return sys.stdin.read().strip()
    return " ".join(words)


def send(args: argparse.Namespace) -> None:
    account = load_account()
    ids = send_to(account, args.to or account.user_id, read_text(args.text), args.file, args.kind)
    if args.json:
        print(json.dumps({"message_ids": ids}))


def print_messages(messages: list[Json], as_json: bool) -> None:
    for m in messages:
        if as_json:
            print(json.dumps(m, ensure_ascii=False), flush=True)
            continue
        stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(m["time"]))
        print(f"[{stamp}] {m['from']}: {m['text']}")
        if quote := m.get("quote"):
            print(f"  > {quote}")
        for a in m.get("attachments", []):
            detail = a.get("path") or a.get("name") or a.get("error") or ""
            print(f"  [{a['type']}] {detail}".rstrip())
        sys.stdout.flush()


def recv(args: argparse.Namespace) -> None:
    account = load_account()
    client = client_for(account)
    while True:
        messages = poll(client, args.wait, args.download)
        print_messages(messages, args.json)
        if not args.follow:
            if not messages:
                sys.exit(3)
            return


def ask(args: argparse.Namespace) -> None:
    account = load_account()
    to = args.to or account.user_id
    send_to(account, to, read_text(args.text), [], None)
    # Anything the peer wrote before the question was sent is backlog, not the answer.
    asked_at = time.time() - ASK_CLOCK_SKEW
    client = client_for(account)
    deadline = time.monotonic() + args.timeout
    while (remaining := deadline - time.monotonic()) > 0:
        messages = poll(client, remaining, args.download)
        replies = [m for m in messages if m["from"] == to and m["time"] >= asked_at]
        # The shared cursor already consumed everything else; surface it rather than drop it.
        others = [m for m in messages if m not in replies]
        if others:
            print_messages(others, args.json)
        if replies:
            print_messages(replies, args.json)
            return
    print("wechat: no reply before timeout", file=sys.stderr)
    sys.exit(3)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="wechat", description="Message your own WeChat.")
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("login", help="bind a bot by scanning a QR code").set_defaults(func=login)
    sub.add_parser("logout", help="forget saved credentials").set_defaults(func=logout)

    s = sub.add_parser("status", help="show login state (exit 1 when logged out)")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=status)

    s = sub.add_parser("send", help="send text and/or files")
    s.add_argument("text", nargs="*", help="message text; `-` or piped stdin reads stdin")
    s.add_argument("--to", help="recipient user id (default: the account that logged in)")
    s.add_argument("--file", "-f", type=Path, action="append", default=[], help="attach a file")
    s.add_argument("--as", dest="kind", choices=["image", "video", "file"], help="force media kind")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=send)

    s = sub.add_parser("recv", help="fetch new incoming messages (exit 3 when none)")
    s.add_argument("--wait", type=float, default=5, help="seconds to wait for a message")
    s.add_argument("--follow", action="store_true", help="keep streaming messages")
    s.add_argument("--download", type=Path, help="save attachments into this directory")
    s.add_argument("--json", action="store_true", help="one JSON object per line")
    s.set_defaults(func=recv)

    s = sub.add_parser("ask", help="send a message and wait for the reply")
    s.add_argument("text", nargs="*")
    s.add_argument("--to")
    s.add_argument("--timeout", type=float, default=600, help="seconds to wait (exit 3 on timeout)")
    s.add_argument("--download", type=Path)
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=ask)
    return p


def main() -> None:
    args = parser().parse_args()
    try:
        args.func(args)
    except KeyboardInterrupt:
        sys.exit(130)
    except (WechatError, OSError, KeyError, ValueError) as error:
        print(f"wechat: {error}", file=sys.stderr)
        sys.exit(1)
