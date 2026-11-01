"""Calls into nix, git and the other tools in the driver's closure."""

from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys
from typing import Any

from . import UpdateError


def placeholder_hash() -> str:
    """A well-formed hash no file holds yet, to pin a fetch before hashing it."""
    return "sha256-" + base64.b64encode(os.urandom(32)).decode()


def run(
    args: list[str], *, capture: bool = False, check: bool = True, **kwargs: Any
) -> subprocess.CompletedProcess[str]:
    """Run a command; without ``capture`` its output goes to the log."""
    shown = (a if "\n" not in a else "<expr>" for a in args)
    print("+", " ".join(shown), file=sys.stderr, flush=True)
    result = subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE if capture else sys.stderr,
        stderr=subprocess.PIPE if capture else None,
        check=False,
        **kwargs,
    )
    if check and result.returncode != 0:
        detail = (result.stderr or "").strip()[-2000:] if capture else ""
        raise UpdateError(f"{args[0]} exited {result.returncode}\n{detail}".rstrip())
    return result


def eval_json(installable: str, apply: str | None = None) -> Any:
    args = ["nix", "eval", "--json", installable]
    if apply is not None:
        args += ["--apply", apply]
    return json.loads(run(args, capture=True).stdout)


def eval_raw(installable: str) -> str:
    return run(["nix", "eval", "--raw", installable], capture=True).stdout


def current_system() -> str:
    return run(
        ["nix", "eval", "--raw", "--impure", "--expr", "builtins.currentSystem"],
        capture=True,
    ).stdout


def build(installable: str) -> str:
    return run(
        ["nix", "build", "--no-link", "--print-out-paths", installable], capture=True
    ).stdout.strip()


def fod_hash(installable: str) -> str:
    """Build a fixed-output derivation pinned to a wrong hash; return the real one."""
    result = run(["nix", "build", "--no-link", installable], capture=True, check=False)
    match = re.search(r"got:\s+(sha\d+-[A-Za-z0-9+/=]+)", result.stderr)
    if match is None:
        raise UpdateError(
            f"building {installable} reported no hash mismatch\n{result.stderr[-2000:]}"
        )
    return match.group(1)


def prefetch(url: str, expected: str | None = None) -> tuple[str, str]:
    """Download a file into the store; return its SRI sha256 and store path."""
    args = ["nix", "store", "prefetch-file", "--json", "--hash-type", "sha256"]
    if expected is not None:
        args += ["--expected-hash", expected]
    data = json.loads(run([*args, url], capture=True).stdout)
    return data["hash"], data["storePath"]


def git(*args: str, capture: bool = True) -> str:
    return run(["git", *args], capture=capture).stdout or ""


def branch_head(repo_url: str) -> str:
    out = git("ls-remote", repo_url, "HEAD").split()
    if not out:
        raise UpdateError(f"{repo_url} has no HEAD")
    return out[0]
