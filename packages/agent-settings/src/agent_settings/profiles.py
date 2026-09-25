"""Named config copies; the default remains Home Manager's stable target."""

import fcntl
import os
import re
import shutil
import tempfile
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path
from typing import final

from agent_settings.documents import edit_document, read_document
from agent_settings.errors import SettingsError


@final
class Profiles:
    def __init__(self, agent: str) -> None:
        self.agent = agent
        self.default = Path.home() / f".{agent}"
        data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        self.directory = data / "agent-settings" / agent / "configs"

    def configurations(self) -> dict[str, Path]:
        result = {"default": self.default}
        if self.directory.exists():
            result.update(
                (p.name, p)
                for p in sorted(self.directory.iterdir())
                if p.is_dir() and not p.is_symlink() and not p.name.startswith(".")
            )
        return result

    def name(self, root: Path) -> str:
        return next(
            (name for name, path in self.configurations().items() if path == root), str(root)
        )

    @contextmanager
    def _lock(self) -> Generator[None]:
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (self.directory / ".manager.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def fork(self, source: Path, name: str, managed_links: list[str]) -> Path:
        with self._lock():
            return self._fork(source, name, managed_links)

    def _fork(self, source: Path, name: str, managed_links: list[str]) -> Path:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", name) or name == "default":
            raise SettingsError(
                "use 1-64 letters, digits, hyphens or underscores; default is reserved"
            )
        target = self.directory / name
        if target.exists() or target.is_symlink():
            raise SettingsError(f"config already exists: {name}")
        temporary = Path(tempfile.mkdtemp(prefix=".fork-", dir=self.directory))
        try:
            # An allowlist keeps tokens, transcripts, caches, and trust state out of forks.
            files = [
                "settings.json" if self.agent == "claude" else "config.toml",
                "dotfiles-settings.json",
                "CLAUDE.md" if self.agent == "claude" else "AGENTS.md",
                "skills",
                "agents",
                "commands",
                "hooks",
                "hooks.json",
                "rules",
            ]
            if self.agent == "codex":
                files.extend(p.name for p in source.glob("*.config.toml"))
            for filename in dict.fromkeys([*files, *managed_links]):
                src, dst = source / filename, temporary / filename
                follows_default = source == self.default or (
                    src.is_symlink() and src.readlink() == self.default / filename
                )
                if filename in managed_links and follows_default:
                    # Resolve through the default path, never pin a Nix store generation.
                    dst.symlink_to(self.default / filename)
                elif src.exists() or src.is_symlink():
                    _copy(src, dst, materialize=filename in files[:2])
            if self.agent == "claude":
                registry = (
                    Path.home() / ".claude.json"
                    if source == self.default
                    else source / ".claude.json"
                )
                mcp = read_document(registry).get("mcpServers", {})
                with edit_document(temporary / ".claude.json") as doc:
                    doc["mcpServers"] = mcp
            temporary.rename(target)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
        return target

    def delete(self, root: Path) -> None:
        with self._lock():
            self._delete(root)

    def _delete(self, root: Path) -> None:
        if root == self.default or root.parent != self.directory or root.is_symlink():
            raise SettingsError("only configs created by this manager can be deleted")
        if root.name not in self.configurations():
            raise SettingsError("config no longer exists")
        shutil.rmtree(root)


def _copy(source: Path, target: Path, *, materialize: bool = False) -> None:
    if source.is_symlink() and not materialize:
        target.symlink_to(source)
    elif source.is_dir():
        target.mkdir(mode=0o700)
        for child in source.iterdir():
            _copy(child, target / child.name)
    else:
        shutil.copyfile(source, target)
        target.chmod(0o600)
