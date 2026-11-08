"""Relay listeners an entry's endpoint is served on, checked before credentials go to them.

Another user on a shared host can bind a relay's port while the relay does
not hold it, and would then receive the API key and every prompt. The
entry's `listenerCheck` (tailnet-relay-check) decides whether this user holds
them, the same check every other client of the relay runs.
"""

import subprocess

from agent_settings.catalog import Entry
from agent_settings.errors import SettingsError


def check_listeners(entry: Entry) -> None:
    """Fail unless this user holds every listener of the entry."""
    listeners = entry.get("listeners", [])
    if not listeners:
        return
    command = entry.get("listenerCheck")
    if command is None:
        raise SettingsError(f"{entry['label']}: listeners without a listenerCheck")
    result = subprocess.run([command, *listeners], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SettingsError(result.stderr.strip() or f"{command} exited {result.returncode}")
