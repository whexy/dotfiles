"""A package being updated, and the edits every kind shares."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import UpdateError, nix
from .pins import replace_once


@dataclass
class Package:
    name: str
    version: str
    system: str
    root: Path
    pname: str = ""
    changelog: str | None = None
    updater: dict[str, Any] = field(default_factory=dict)

    @property
    def dir(self) -> Path:
        return self.root / "packages" / self.name

    def attr(self, path: str = "") -> str:
        """The flake installable for this package, or one of its attributes."""
        base = f"{self.root}#packages.{self.system}.{self.name}"
        return f"{base}.{path}" if path else base

    @classmethod
    def from_env(cls) -> Package:
        """The package a ``script`` kind's update.py runs for."""
        try:
            name = os.environ["UPDATE_PACKAGE"]
            system = os.environ["UPDATE_SYSTEM"]
            root = Path(os.environ["UPDATE_ROOT"])
            version = os.environ["UPDATE_VERSION"]
            updater = json.loads(os.environ["UPDATE_CONFIG"])
        except KeyError as error:
            raise UpdateError(f"update.py runs under the driver ({error} unset)") from error
        return cls(
            name=name, version=version, system=system, root=root, pname=name, updater=updater
        )

    def _file_containing(self, text: str) -> Path:
        files = [
            path
            for path in sorted(self.dir.rglob("*"))
            if path.suffix in {".nix", ".json"} and text in path.read_text()
        ]
        if len(files) != 1:
            raise UpdateError(f"{self.name}: {text!r} is in {len(files)} files, not one")
        return files[0]

    def refresh_hash(self, attr: str) -> None:
        """Re-pin a fixed-output attribute whose inputs already changed."""
        old = nix.eval_raw(self.attr(f"{attr}.outputHash"))
        path = self._file_containing(old)
        placeholder = nix.placeholder_hash()
        replace_once(path, old, placeholder)
        new = nix.fod_hash(self.attr(attr))
        replace_once(path, placeholder, new)
        print(f"{self.name}.{attr}: {new}")

    def follow_branch(self, attr: str) -> None:
        """Move a git fetcher to its repository's default-branch head."""
        info = nix.eval_json(self.attr(attr), apply="f: { inherit (f) rev gitRepoUrl; }")
        head = nix.branch_head(info["gitRepoUrl"])
        if head == info["rev"]:
            return
        replace_once(self._file_containing(info["rev"]), info["rev"], head)
        self.refresh_hash(attr)
