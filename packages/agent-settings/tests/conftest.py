import os
from collections.abc import Callable, Iterator
from pathlib import Path
from unittest.mock import patch

import pytest
from support import SECRET, manifest, model_entry

from agent_settings.agents import Agent, create_agent


@pytest.fixture
def home(tmp_path: Path) -> Iterator[Path]:
    """An isolated home and an otherwise empty environment."""
    with patch.dict(os.environ, {"HOME": str(tmp_path)}, clear=True):
        yield tmp_path


@pytest.fixture
def secret(home: Path) -> Path:
    path = home / "secret"
    path.write_text(f"{SECRET}\n")
    return path


@pytest.fixture
def make_agent(secret: Path) -> Callable[[str], Agent]:
    """Build an agent offering the native login and one API model."""

    def make(name: str) -> Agent:
        return create_agent(manifest(name, [model_entry(name, secret)]))

    return make
