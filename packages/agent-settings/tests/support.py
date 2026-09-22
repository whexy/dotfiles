import contextlib
import os
import sys
from collections.abc import Generator
from pathlib import Path
from unittest.mock import patch

import pytest

from agent_settings.agents import Agent
from agent_settings.catalog import Entry, Manifest

AGENT_NAMES = ("claude", "codex")
SECRET = "test-key"


def model_entry(agent: str, secret: Path, label: str = "api/model", model: str = "model") -> Entry:
    if agent == "codex":
        return {
            "label": label,
            "secrets": {"OPENAI_API_KEY": str(secret)},
            "settings": {
                "model": model,
                "model_provider": "dotfiles-test",
                "model_providers": {
                    "dotfiles-test": {
                        "name": "test",
                        "env_key": "OPENAI_API_KEY",
                        "requires_openai_auth": False,
                    }
                },
            },
        }
    return {
        "label": label,
        "secrets": {"ANTHROPIC_API_KEY": str(secret)},
        "env": {"ANTHROPIC_MODEL": model, "ANTHROPIC_BASE_URL": "https://test.invalid"},
    }


def manifest(agent: str, entries: list[Entry]) -> Manifest:
    return {
        "name": agent,
        "real": "/fake/agent",
        "fzf": "/fake/fzf",
        "entries": [{"label": "default"}, *entries],
        "mcpServers": {"owned": {"command": "/new/server"}},
        "maintainedSettings": {},
        "resetEnv": [],
    }


def launch(agent: Agent, args: list[str] | None = None) -> tuple[str, list[str], dict[str, str]]:
    """Launch without replacing the test process; return the execve arguments."""
    with patch.object(os, "execve", side_effect=SystemExit) as execute, pytest.raises(SystemExit):
        agent.launch(args or [])
    path, argv, env = execute.call_args.args
    return path, argv, env


@contextlib.contextmanager
def terminal() -> Generator[None]:
    with (
        patch.object(sys.stdin, "isatty", return_value=True),
        patch.object(sys.stdout, "isatty", return_value=True),
    ):
        yield
