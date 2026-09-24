"""`wechat status | send | ask`, a client of the wechat-relay service."""

import argparse
import contextlib
import json
import sys
import time
from pathlib import Path

from wechat_cli.relay import Json, Relay, RelayError

# Long-poll slice for GET /api/asks/{id}; the relay caps it at 60.
ASK_POLL = 30
# The relay expires an ask at its timeout but only notices on its next tick.
ASK_GRACE = 90.0
RETRY_DELAY = 5.0


def status(args: argparse.Namespace) -> None:
    relay = Relay()
    st = relay.status()
    online = st.get("state") == "online"
    if args.json:
        print(json.dumps(st, ensure_ascii=False))
    elif online:
        if st.get("window_open"):
            print(f"online; send window open for {st.get('window_remaining')}")
        else:
            print("online; send window closed, messages queue until the user writes to the bot")
        if queued := st.get("queued"):
            print(f"{queued} message(s) queued")
        if holding := st.get("holding"):
            print(f"awaiting a reply to: {holding.get('text')}")
    else:
        print(f"relay is {st.get('state')}; open {relay.url} and scan the QR code with WeChat")
    if not online:
        sys.exit(1)


def read_text(words: list[str]) -> str:
    if words == ["-"] or (not words and not sys.stdin.isatty()):
        return sys.stdin.read().strip()
    return " ".join(words)


def check_files(files: list[Path]) -> None:
    for path in files:
        if not path.is_file():
            raise RelayError(f"no such file: {path}")


def post(relay: Relay, args: argparse.Namespace, require_reply: bool = False) -> Json:
    text = read_text(args.text)
    check_files(args.file)
    if not text and not args.file:
        raise RelayError("nothing to send: give text, --file, or pipe text on stdin")
    timeout = args.timeout if require_reply else None
    code, resp = relay.send(text, args.file, args.kind, require_reply, timeout)
    if code == 202:
        print(f"queued: {resp.get('reason')}", file=sys.stderr)
    return resp


def send(args: argparse.Namespace) -> None:
    resp = post(Relay(), args)
    if args.json:
        print(json.dumps(resp, ensure_ascii=False))


def save_attachments(relay: Relay, ask_id: str, reply: Json, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for n, att in enumerate(reply.get("attachments") or []):
        if not att.get("url"):
            continue
        # Prefix the ask and index so attachments with the same name never collide.
        path = dest / f"{ask_id}-{n}-{Path(att.get('name') or 'file').name}"
        try:
            path.write_bytes(relay.fetch(att["url"]))
            att["path"] = str(path)
        except RelayError as error:
            att["error"] = str(error)


def print_reply(reply: Json, as_json: bool) -> None:
    for att in reply.get("attachments") or []:
        att.pop("url", None)
    if as_json:
        print(json.dumps(reply, ensure_ascii=False))
        return
    if quote := reply.get("quote"):
        print(f"> {quote}")
    if reply.get("text"):
        print(reply["text"])
    for att in reply.get("attachments") or []:
        detail = att.get("path") or att.get("name") or ""
        if error := att.get("error"):
            detail = f"{detail} ({error})".strip()
        print(f"[{att['kind']}] {detail}".rstrip())


def wait_reply(relay: Relay, ask_id: str, deadline: float) -> Json | None:
    """Poll the ask until it resolves; None means it ended without a reply."""
    while True:
        try:
            ask = relay.wait_ask(ask_id, ASK_POLL)
        except RelayError as error:
            if not error.transient or time.monotonic() > deadline:
                raise
            time.sleep(RETRY_DELAY)
            continue
        match ask.get("state"):
            case "answered":
                return ask.get("reply") or {}
            case "expired":
                return None
            case "cancelled":
                raise RelayError("the question was cancelled on the relay")
            case "failed":
                raise RelayError(f"the question could not be delivered: {ask.get('error')}")
            case _:
                if time.monotonic() > deadline:
                    relay.cancel(ask_id)
                    return None


def ask(args: argparse.Namespace) -> None:
    relay = Relay()
    ask_id: str = post(relay, args, require_reply=True)["ask_id"]
    try:
        reply = wait_reply(relay, ask_id, time.monotonic() + args.timeout + ASK_GRACE)
    except KeyboardInterrupt:
        # Release the hold so the next client's messages are not stuck behind us.
        with contextlib.suppress(RelayError):
            relay.cancel(ask_id)
        raise
    if reply is None:
        print("wechat: no reply before timeout", file=sys.stderr)
        sys.exit(3)
    if args.download:
        save_attachments(relay, ask_id, reply, args.download)
    print_reply(reply, args.json)


def add_message_args(s: argparse.ArgumentParser) -> None:
    s.add_argument("text", nargs="*", help="message text; `-` or piped stdin reads stdin")
    s.add_argument("--file", "-f", type=Path, action="append", default=[], help="attach a file")
    s.add_argument("--as", dest="kind", choices=["image", "video", "file"], help="force media kind")
    s.add_argument("--json", action="store_true")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wechat",
        description="Message your own WeChat through the wechat-relay service ($WECHAT_RELAY_URL).",
    )
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("status", help="show relay state (exit 1 unless online)")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=status)

    s = sub.add_parser("send", help="send text and/or files")
    add_message_args(s)
    s.set_defaults(func=send)

    s = sub.add_parser("ask", help="send a question and wait for the reply (exit 3 on timeout)")
    add_message_args(s)
    s.add_argument(
        "--timeout",
        type=float,
        default=600,
        help="seconds from now until the question lapses, including time queued (max 86400)",
    )
    s.add_argument("--download", type=Path, help="save reply attachments into this directory")
    s.set_defaults(func=ask)
    return p


def main() -> None:
    args = parser().parse_args()
    try:
        args.func(args)
    except KeyboardInterrupt:
        sys.exit(130)
    except (RelayError, OSError, KeyError, ValueError) as error:
        print(f"wechat: {error}", file=sys.stderr)
        sys.exit(1)
