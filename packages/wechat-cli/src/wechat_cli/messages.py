"""Translate between WeChat wire messages and what the CLI prints or sends."""

import secrets
import time
from pathlib import Path

from wechat_cli import media
from wechat_cli.api import LONG_POLL_TIMEOUT, Client, Json, WechatError
from wechat_cli.state import load_sync, sync_lock

MESSAGE_TYPE_USER = 1
MESSAGE_TYPE_BOT = 2
MESSAGE_STATE_FINISH = 2

ITEM_LABELS = {
    media.ITEM_IMAGE: "image",
    media.ITEM_VOICE: "voice",
    media.ITEM_FILE: "file",
    media.ITEM_VIDEO: "video",
}


def outbound(to: str, item: Json, context_token: str | None) -> Json:
    msg: Json = {
        "from_user_id": "",
        "to_user_id": to,
        "client_id": f"wechat-cli-{secrets.token_hex(8)}",
        "message_type": MESSAGE_TYPE_BOT,
        "message_state": MESSAGE_STATE_FINISH,
        "item_list": [item],
    }
    if context_token:
        msg["context_token"] = context_token
    return msg


def text_item(text: str) -> Json:
    return {"type": media.ITEM_TEXT, "text_item": {"text": text}}


def summarize(msg: Json, download_dir: Path | None) -> Json:
    """Flatten a message into text plus one entry per attachment."""
    texts: list[str] = []
    attachments: list[Json] = []
    quote: str | None = None
    for item in msg.get("item_list") or []:
        kind = item.get("type")
        if kind == media.ITEM_TEXT:
            texts.append((item.get("text_item") or {}).get("text") or "")
        elif kind in ITEM_LABELS:
            attachment: Json = {"type": ITEM_LABELS[kind]}
            if kind == media.ITEM_VOICE:
                # WeChat transcribes voice notes server-side.
                transcript = (item.get("voice_item") or {}).get("text")
                if transcript:
                    texts.append(transcript)
                    attachment["transcript"] = transcript
            if kind == media.ITEM_FILE:
                attachment["name"] = (item.get("file_item") or {}).get("file_name")
            if download_dir is not None:
                try:
                    stem = str(msg.get("message_id") or msg.get("seq") or int(time.time()))
                    attachment["path"] = str(media.download(item, download_dir, stem))
                except WechatError as error:
                    attachment["error"] = str(error)
            attachments.append(attachment)
        ref = item.get("ref_msg") or {}
        if ref:
            quoted = (ref.get("message_item") or {}).get("text_item") or {}
            quote = quoted.get("text") or ref.get("title")
    summary: Json = {
        "id": str(msg.get("message_id") or ""),
        "from": msg.get("from_user_id") or "",
        "time": (msg.get("create_time_ms") or 0) / 1000,
        "text": "\n".join(texts),
    }
    if quote:
        summary["quote"] = quote
    if attachments:
        summary["attachments"] = attachments
    return summary


def poll(client: Client, wait: float, download_dir: Path | None) -> list[Json]:
    """Long-poll until at least one user message arrives or `wait` seconds pass.

    The cursor advances only after a batch is handed back, so an interrupted
    poll replays rather than loses messages.
    """
    deadline = time.monotonic() + wait
    with sync_lock():
        sync = load_sync()
        while True:
            remaining = deadline - time.monotonic()
            resp = client.get_updates(
                sync.cursor, timeout=max(1.0, min(remaining, LONG_POLL_TIMEOUT))
            )
            incoming = [
                m for m in resp.get("msgs") or [] if m.get("message_type") != MESSAGE_TYPE_BOT
            ]
            for m in incoming:
                if m.get("from_user_id") and m.get("context_token"):
                    sent_at = (m.get("create_time_ms") or 0) / 1000 or time.time()
                    sync.remember(m["from_user_id"], m["context_token"], sent_at)
            summaries = [summarize(m, download_dir) for m in incoming]
            if resp.get("get_updates_buf"):
                sync.cursor = resp["get_updates_buf"]
            sync.save()
            if summaries or time.monotonic() >= deadline:
                return summaries
