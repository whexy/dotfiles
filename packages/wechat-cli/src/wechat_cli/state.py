"""Credentials and sync state under `$XDG_STATE_HOME/wechat-cli`."""

import fcntl
import json
import os
from collections.abc import Generator
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from wechat_cli.api import DEFAULT_BASE_URL, WechatError


def state_dir() -> Path:
    if override := os.environ.get("WECHAT_CLI_STATE_DIR"):
        return Path(override)
    xdg = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(xdg) / "wechat-cli"


def _read(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return None


def _write(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_suffix(".tmp")
    # The bot token grants full control of the bot, so never let it be world-readable.
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
    tmp.replace(path)


@dataclass
class Account:
    token: str
    bot_id: str
    user_id: str
    base_url: str = DEFAULT_BASE_URL


def load_account() -> Account:
    data = _read(state_dir() / "account.json")
    if not data:
        raise WechatError("not logged in; run `wechat login`")
    return Account(**data)


def load_account_or_none() -> Account | None:
    data = _read(state_dir() / "account.json")
    return Account(**data) if data else None


def save_account(account: Account) -> None:
    _write(state_dir() / "account.json", asdict(account))
    # A new bot starts from an empty cursor; old context tokens belong to the old bot.
    (state_dir() / "sync.json").unlink(missing_ok=True)


def forget() -> bool:
    removed = False
    for name in ("account.json", "sync.json"):
        path = state_dir() / name
        if path.exists():
            path.unlink()
            removed = True
    return removed


# The backend accepts a context token for 24 hours after the message that carried it.
CONTEXT_TTL = 24 * 3600.0


@dataclass
class Sync:
    """The getupdates cursor plus the newest context token each peer sent.

    The bot can only send inside a conversation the peer started, by quoting
    the context token of the peer's latest message.
    """

    cursor: str = ""
    context_tokens: dict[str, str] = field(default_factory=dict)
    context_received: dict[str, float] = field(default_factory=dict)

    def remember(self, peer: str, token: str, at: float) -> None:
        self.context_tokens[peer] = token
        self.context_received[peer] = at

    def send_window(self, peer: str, now: float) -> float | None:
        """Seconds left to send to `peer`, or None when it never wrote."""
        if peer not in self.context_tokens:
            return None
        return self.context_received.get(peer, now) + CONTEXT_TTL - now

    def save(self) -> None:
        _write(state_dir() / "sync.json", asdict(self))


def load_sync() -> Sync:
    data = _read(state_dir() / "sync.json")
    return Sync(**data) if data else Sync()


@contextmanager
def sync_lock() -> Generator[None]:
    """Serialise cursor updates so concurrent agents never replay or drop a batch."""
    path = state_dir() / "sync.lock"
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield
