"""Pure helpers for pins: hashes, templates, versions, sources.json."""

from __future__ import annotations

import base64
import json
import re
from typing import TYPE_CHECKING, Any

from . import UpdateError

if TYPE_CHECKING:
    from pathlib import Path

SOURCES = "sources.json"


def hex_to_sri(digest: str) -> str:
    """Convert a hex digest to an SRI hash, choosing the algorithm by length."""
    algo = {64: "sha256", 128: "sha512"}.get(len(digest))
    if algo is None or not re.fullmatch(r"[0-9a-fA-F]+", digest):
        raise UpdateError(f"not a sha256 or sha512 hex digest: {digest!r}")
    return f"{algo}-{base64.b64encode(bytes.fromhex(digest)).decode()}"


def b64_to_sri(algo: str, digest: str) -> str:
    base64.b64decode(digest, validate=True)
    return f"{algo}-{digest}"


def interpolate(template: str, **values: str) -> str:
    """Fill ``{name}`` placeholders; an unknown placeholder is an error."""

    def fill(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in values:
            raise UpdateError(f"template {template!r} has no value for {{{name}}}")
        return values[name]

    return re.sub(r"\{([a-z_]+)\}", fill, template)


def dig(document: Any, path: str) -> Any:
    """Follow a dotted key path into nested objects."""
    current = document
    for key in path.split("."):
        if not isinstance(current, dict) or key not in current:
            raise UpdateError(f"no {path!r} in the document (stopped at {key!r})")
        current = current[key]
    return current


def strip_v(tag: str) -> str:
    return tag[1:] if re.match(r"v\d", tag) else tag


def _components(version: str) -> list[str]:
    return re.findall(r"\d+|[^\d.\-]+", version)


def _less(a: str, b: str) -> bool:
    if a.isdigit() and b.isdigit():
        return int(a) < int(b)
    if a == "" and b.isdigit():
        return True
    if a == "pre" and b != "pre":
        return True
    if b == "pre":
        return False
    if b.isdigit():
        return True
    if a.isdigit():
        return False
    return a < b


def compare_versions(a: str, b: str) -> int:
    """Order two versions the way ``builtins.compareVersions`` does."""
    left, right = _components(a), _components(b)
    for i in range(max(len(left), len(right))):
        x = left[i] if i < len(left) else ""
        y = right[i] if i < len(right) else ""
        if _less(x, y):
            return -1
        if _less(y, x):
            return 1
    return 0


def read_sources(pkg_dir: Path) -> dict[str, Any]:
    path = pkg_dir / SOURCES
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def write_sources(pkg_dir: Path, data: dict[str, Any]) -> None:
    """Write sources.json in the layout prettier keeps."""
    (pkg_dir / SOURCES).write_text(json.dumps(data, indent=2) + "\n")


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise UpdateError(f"{path}: expected one {old!r}, found {count}")
    path.write_text(text.replace(old, new))
