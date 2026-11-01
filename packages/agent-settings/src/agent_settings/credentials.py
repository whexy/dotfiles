"""Credentials the catalog names, loaded only when an agent launches."""

import subprocess
from collections.abc import Mapping, Sequence

from agent_settings.errors import SettingsError


def read_secrets(secrets: Mapping[str, Sequence[str]]) -> dict[str, str]:
    """Run each credential's command, all at once, for its single-line value."""
    try:
        running = {
            key: subprocess.Popen(
                list(command),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                text=True,
            )
            for key, command in secrets.items()
        }
    except OSError as error:
        raise SettingsError(f"could not load credentials: {error}") from error
    values: dict[str, str] = {}
    for key, process in running.items():
        output, _ = process.communicate()
        value = output.rstrip("\n")
        if process.returncode != 0 or not value or "\n" in value or "\r" in value:
            raise SettingsError(f"missing or invalid credential for {key}")
        values[key] = value
    return values
