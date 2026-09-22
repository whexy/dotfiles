import os
import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest

from agent_settings.credentials import read_secrets, secret_path
from agent_settings.errors import SettingsError


@pytest.mark.parametrize(
    "command",
    [
        "getconf",
        "/usr/bin/getconf",
        "/nix/store/bk9qiyaah5manlrb6hvqh0dyf1dk7wn8-getconf-system_cmds-1039/bin/getconf",
    ],
)
def test_agenix_darwin_temp_dir(command: str) -> None:
    with patch.object(
        subprocess, "check_output", return_value="/var/folders/fixture/T/\n"
    ) as getconf:
        path = secret_path(f"$({command} DARWIN_USER_TEMP_DIR)/agenix/key")
    assert path == Path("/var/folders/fixture/T/agenix/key")
    getconf.assert_called_once_with(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"], text=True)


def test_environment_and_absolute_paths() -> None:
    with patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1000"}):
        assert secret_path("${XDG_RUNTIME_DIR}/agenix/key") == Path("/run/user/1000/agenix/key")
    assert secret_path("/run/agenix/key") == Path("/run/agenix/key")


@pytest.mark.parametrize(
    "fragment",
    [
        "$(touch /tmp/unsafe)/agenix/key",
        "$(getconf DARWIN_USER_TEMP_DIR; echo unsafe)/agenix/key",
        "$(/tmp/getconf DARWIN_USER_TEMP_DIR)/agenix/key",
        "$(getconf DARWIN_USER_TEMP_DIR)/$(echo unsafe)",
        "${UNDEFINED_CREDENTIAL_ROOT}/agenix/key",
        "relative/key",
    ],
)
@pytest.mark.usefixtures("home")
def test_rejects_arbitrary_commands(fragment: str) -> None:
    with patch.object(subprocess, "check_output") as execute, pytest.raises(SettingsError):
        secret_path(fragment)
    execute.assert_not_called()


@pytest.mark.parametrize("content", ["", "\n", "two\nlines\n", "carriage\rreturn"])
def test_rejects_empty_or_multiline_secrets(home: Path, content: str) -> None:
    path = home / "secret"
    path.write_text(content)
    with pytest.raises(SettingsError):
        read_secrets({"KEY": str(path)})
