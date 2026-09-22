"""Credential files named by the catalog, read only when an agent launches."""

import os
import re
import subprocess
from collections.abc import Mapping
from pathlib import Path

from agent_settings.errors import SettingsError

# Agenix may qualify getconf with its Nix store path. Recognize only this
# substitution and run the system utility, never a command from the catalog.
_DARWIN_TEMP_DIR = re.compile(
    r"""
    \$\(
        (?: getconf | /usr/bin/getconf | /nix/store/[a-z0-9]{32}-[A-Za-z0-9+._?=-]+/bin/getconf )
        \ DARWIN_USER_TEMP_DIR
    \)
    (/[^$]*)
    """,
    re.VERBOSE,
)


def secret_path(fragment: str) -> Path:
    """Resolve an agenix secret path as written in the catalog."""
    darwin = _DARWIN_TEMP_DIR.fullmatch(fragment)
    if darwin:
        temporary = subprocess.check_output(
            ["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"], text=True
        ).strip()
        fragment = temporary.rstrip("/") + darwin.group(1)
    fragment = os.path.expandvars(fragment)
    if "$" in fragment or not fragment.startswith("/"):
        raise SettingsError("unresolved credential path")
    return Path(fragment)


def read_secrets(secrets: Mapping[str, str]) -> dict[str, str]:
    """Read each single-line credential into its environment variable."""
    values: dict[str, str] = {}
    for key, fragment in secrets.items():
        value = secret_path(fragment).read_text().rstrip("\n")
        if not value or "\n" in value or "\r" in value:
            raise SettingsError(f"missing or invalid credential for {key}")
        values[key] = value
    return values
