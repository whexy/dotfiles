import os
from collections.abc import Iterator
from pathlib import Path
from typing import Any, override
from unittest.mock import patch

import pytest

from wechat_cli import api, messages
from wechat_cli.state import CONTEXT_TTL, Account, Sync, load_sync, save_account


@pytest.fixture(autouse=True)
def state(tmp_path: Path) -> Iterator[Path]:
    with patch.dict(os.environ, {"WECHAT_CLI_STATE_DIR": str(tmp_path)}):
        yield tmp_path


class FakeClient(api.Client):
    def __init__(self, batches: list[dict[str, Any]]) -> None:
        super().__init__(token="t")
        self.batches: list[dict[str, Any]] = batches
        self.cursors: list[str] = []

    @override
    def get_updates(self, cursor: str, timeout: float = api.LONG_POLL_TIMEOUT) -> api.Json:
        self.cursors.append(cursor)
        return self.batches.pop(0) if self.batches else {"msgs": [], "get_updates_buf": cursor}


def user_msg(text: str, sender: str = "me@im.wechat", token: str = "ctx") -> api.Json:
    return {
        "message_id": 12345678901234567890,
        "from_user_id": sender,
        "message_type": messages.MESSAGE_TYPE_USER,
        "create_time_ms": 1_700_000_000_000,
        "context_token": token,
        "item_list": [{"type": 1, "text_item": {"text": text}}],
    }


def test_poll_advances_cursor_and_remembers_context_token() -> None:
    client = FakeClient([{"msgs": [user_msg("hi")], "get_updates_buf": "c1"}])
    got = messages.poll(client, wait=0, download_dir=None)
    assert [m["text"] for m in got] == ["hi"]
    assert got[0]["id"] == "12345678901234567890"
    sync = load_sync()
    assert sync.cursor == "c1"
    assert sync.context_tokens == {"me@im.wechat": "ctx"}
    assert sync.context_received == {"me@im.wechat": 1_700_000_000.0}

    messages.poll(client, wait=0, download_dir=None)
    assert client.cursors == ["", "c1"]


def test_poll_skips_bot_echoes() -> None:
    echo = user_msg("from bot") | {"message_type": messages.MESSAGE_TYPE_BOT}
    client = FakeClient([{"msgs": [echo], "get_updates_buf": "c1"}])
    assert messages.poll(client, wait=0, download_dir=None) == []


def test_summarize_voice_transcript_and_quote() -> None:
    msg = {
        "from_user_id": "me",
        "item_list": [
            {"type": 3, "voice_item": {"text": "spoken words"}},
            {
                "type": 1,
                "text_item": {"text": "reply"},
                "ref_msg": {"message_item": {"text_item": {"text": "original"}}},
            },
        ],
    }
    summary = messages.summarize(msg, None)
    assert summary["text"] == "spoken words\nreply"
    assert summary["quote"] == "original"
    assert summary["attachments"] == [{"type": "voice", "transcript": "spoken words"}]


def test_outbound_attaches_context_token_only_when_known() -> None:
    item = messages.text_item("hello")
    with_ctx = messages.outbound("u", item, "ctx")
    assert with_ctx["context_token"] == "ctx"
    assert with_ctx["message_type"] == messages.MESSAGE_TYPE_BOT
    assert "context_token" not in messages.outbound("u", item, None)


def test_new_login_resets_sync_state(state: Path) -> None:
    Sync(cursor="old", context_tokens={"a": "b"}).save()
    save_account(Account(token="t", bot_id="b", user_id="u"))
    assert load_sync().cursor == ""
    assert (state / "account.json").stat().st_mode & 0o077 == 0


def test_check_maps_stale_token() -> None:
    with pytest.raises(api.SessionExpired):
        api.check({"errcode": api.STALE_TOKEN_ERRCODE}, "x")
    with pytest.raises(api.WechatError):
        api.check({"ret": 1, "errmsg": "bad"}, "x")
    assert api.check({"ret": 0}, "x") == {"ret": 0}


def test_client_version_packing() -> None:
    assert api._client_version("1.0.11") == 65547


def test_send_window_counts_down_from_the_peers_message() -> None:
    sync = Sync()
    assert sync.send_window("me", now=1000.0) is None
    sync.remember("me", "ctx", at=1000.0)
    assert sync.send_window("me", now=1000.0 + 3600) == CONTEXT_TTL - 3600
    assert sync.send_window("me", now=1000.0 + CONTEXT_TTL + 60) == -60
