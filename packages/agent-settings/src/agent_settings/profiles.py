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


def muse_config_home() -> Path:
    """The user's real XDG config home, ignoring a named config's export.

    A launched named config sets XDG_CONFIG_HOME to its own container; that
    must not move the default config it was forked from.
    """
    home = Path.home()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")).expanduser()
    data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")).expanduser()
    configs = data / "agent-settings" / "muse" / "configs"
    if config_home == configs or configs in config_home.parents:
        return home / ".config"
    return config_home


@final
class Profiles:
    def __init__(
        self,
        agent: str,
        config_name: str | None = None,
        default: Path | None = None,
        subdir: str = "",
    ) -> None:
        self.agent = agent
        self.config_name = config_name or ("config.toml" if agent == "codex" else "settings.json")
        # Muse's config directory is `muse` under the XDG config home, and a
        # named config relocates that home, so its root sits one level deeper.
        self.subdir = subdir or ("muse" if agent == "muse" else "")
        if default is not None:
            self.default = default
        elif agent == "muse":
            self.default = muse_config_home() / "muse"
        else:
            self.default = Path.home() / f".{agent}"
        data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        self.directory = data / "agent-settings" / agent / "configs"

    def root_in(self, container: Path) -> Path:
        return container / self.subdir if self.subdir else container

    def container(self, root: Path) -> Path:
        return root.parent if self.subdir else root

    def is_managed(self, root: Path) -> bool:
        """Whether `root` is a named config this manager may delete."""
        container = self.container(root)
        return root != self.default and container.parent == self.directory

    def configurations(self) -> dict[str, Path]:
        result = {"default": self.default}
        if self.directory.exists():
            result.update(
                (p.name, self.root_in(p))
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
        root = self.root_in(temporary)
        root.mkdir(parents=True, exist_ok=True)
        try:
            # An allowlist keeps tokens, transcripts, caches, and trust state out of forks.
            files = [
                self.config_name,
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
                src, dst = source / filename, root / filename
                follows_default = source == self.default or (
                    src.is_symlink() and src.readlink() == self.default / filename
                )
                if filename in managed_links and follows_default:
                    # Resolve through the default path, never pin a Nix store generation.
                    dst.symlink_to(self.default / filename)
                elif src.exists() or src.is_symlink():
                    # Links resolve through the source, following its Home
                    # Manager generations, unless it is a config this manager
                    # can delete; those links are copied as they are.
                    _copy(
                        src,
                        dst,
                        materialize=filename in files[:2],
                        through_source=self.container(source).parent != self.directory,
                    )
            if self.agent == "claude":
                registry = (
                    Path.home() / ".claude.json"
                    if source == self.default
                    else source / ".claude.json"
                )
                mcp = read_document(registry).get("mcpServers", {})
                with edit_document(root / ".claude.json") as doc:
                    doc["mcpServers"] = mcp
            temporary.rename(target)
            return self.root_in(target)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)

    def delete(self, root: Path) -> None:
        with self._lock():
            self._delete(root)

    def _delete(self, root: Path) -> None:
        container = self.container(root)
        if root == self.default or container.parent != self.directory or container.is_symlink():
            raise SettingsError("only configs created by this manager can be deleted")
        if container.name not in self.configurations():
            raise SettingsError("config no longer exists")
        shutil.rmtree(container)


def _copy(source: Path, target: Path, *, materialize: bool = False, through_source: bool) -> None:
    if source.is_symlink() and not materialize:
        target.symlink_to(source if through_source else source.readlink())
    elif source.is_dir():
        target.mkdir(mode=0o700)
        for child in source.iterdir():
            _copy(child, target / child.name, through_source=through_source)
    else:
        shutil.copyfile(source, target)
        # Hook scripts must stay executable.
        target.chmod(0o700 if source.stat().st_mode & 0o100 else 0o600)
