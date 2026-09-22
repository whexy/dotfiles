"""JSON and TOML documents that both the user and Nix edit.

Writers serialize on an advisory lock beside each document, write a
same-directory temporary file, and replace the original only if it is unchanged
since it was read. Agents ignore the lock, so that final check narrows the race
with them but cannot close it.
"""

import contextlib
import fcntl
import json
import os
import tempfile
from collections.abc import Generator
from pathlib import Path
from typing import TypeIs, cast

import tomlkit

from agent_settings.errors import SettingsError

# Values stay `object`: every assumption about a user-editable file is an
# explicit check rather than a crash deep inside a merge.
type Table = dict[str, object]
type _Fingerprint = tuple[int, int, bytes] | None


def is_table(value: object) -> TypeIs[Table]:
    return isinstance(value, dict)


def is_list(value: object) -> TypeIs[list[object]]:
    return isinstance(value, list)


def table_or_empty(value: object) -> Table:
    return value if is_table(value) else {}


def child_table(doc: Table, key: str) -> Table:
    """Return the table at `key`, creating it when absent."""
    value = doc.setdefault(key, {})
    if not is_table(value):
        raise SettingsError(f"expected a table/object at {key}")
    return value


def read_document(path: Path) -> Table:
    """Parse `path`, or return an empty document when it does not exist."""
    if not path.exists() and not path.is_symlink():
        return tomlkit.document() if _is_toml(path) else {}
    text = path.read_text()
    doc = cast(object, tomlkit.parse(text) if _is_toml(path) else json.loads(text))
    if not is_table(doc):
        raise SettingsError(f"expected an object in {path}")
    return doc


@contextlib.contextmanager
def edit_document(path: Path) -> Generator[Table]:
    """Yield the parsed document, then save it unless another writer changed it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.parent / f".{path.name}.dotfiles.lock"
    with lock_path.open("a") as lock:
        lock_path.chmod(0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        before = _fingerprint(path)
        doc = read_document(path)
        yield doc
        _save(path, doc, before)


def _is_toml(path: Path) -> bool:
    return path.suffix == ".toml"


def _dumps(path: Path, doc: Table) -> str:
    if _is_toml(path):
        # tomlkit annotates its API with bare generics.
        return tomlkit.dumps(doc)  # pyright: ignore[reportUnknownMemberType]
    return json.dumps(doc, indent=2) + "\n"


def _fingerprint(path: Path) -> _Fingerprint:
    if not path.exists() and not path.is_symlink():
        return None
    stat = path.lstat()
    return (stat.st_ino, stat.st_mtime_ns, path.read_bytes())


def _save(path: Path, doc: Table, before: _Fingerprint) -> None:
    # Links into the store are Home Manager generations being materialized;
    # any other link points at a file someone else owns.
    if path.is_symlink() and not str(path.resolve()).startswith("/nix/store/"):
        raise SettingsError(f"refusing to replace non-Nix symlink: {path}")
    text = _dumps(path, doc)
    if before is not None and before[2] == text.encode() and not path.is_symlink():
        return
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w") as target:
            target.write(text)
            target.flush()
            os.fsync(target.fileno())
        if _fingerprint(path) != before:
            raise SettingsError(f"{path} changed while editing; retry")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
