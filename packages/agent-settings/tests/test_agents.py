import json
import os
import sys
from collections.abc import Callable
from pathlib import Path
from unittest.mock import patch

import pytest
import tomlkit
from support import AGENT_NAMES, SECRET, launch, manifest, model_entry, terminal

from agent_settings.agents import Agent, create_agent
from agent_settings.catalog import Entry
from agent_settings.documents import read_document
from agent_settings.errors import SettingsError

type MakeAgent = Callable[[str], Agent]


def default(agent: Agent) -> Entry:
    return agent.catalog.choices[0]


def api_model(agent: Agent) -> Entry:
    return agent.catalog.choices[1]


@pytest.mark.parametrize("name", AGENT_NAMES)
def test_selection_persists_without_secrets(make_agent: MakeAgent, name: str) -> None:
    agent = make_agent(name)
    agent.reconcile(api_model(agent))
    path, argv, env = launch(agent, ["--help"])
    if name == "codex":
        assert argv == [path, "--help"]
    else:
        assert argv[-1] == "--help"
        assert json.loads(argv[2])["env"]["ANTHROPIC_BASE_URL"] == "https://test.invalid"
    assert SECRET in env.values()
    for saved in (agent.config_file.read_text(), agent.state_file.read_text()):
        assert SECRET not in saved
    assert SECRET not in env[agent.session_env]
    assert agent.config_file.stat().st_mode & 0o777 == 0o600


@pytest.mark.parametrize("name", AGENT_NAMES)
def test_default_login_removes_overrides_and_keeps_auth(make_agent: MakeAgent, name: str) -> None:
    agent = make_agent(name)
    agent.reconcile(api_model(agent))
    auth = agent.root / "auth.json"
    auth.write_text('{"login":"untouched"}')
    agent.reconcile(default(agent))
    doc = read_document(agent.config_file)
    assert "model" not in doc
    assert "model_provider" not in doc
    if name == "claude":
        assert doc["env"] == {}
    _, _, env = launch(agent)
    assert SECRET not in env.values()
    assert auth.read_text() == '{"login":"untouched"}'


@pytest.mark.parametrize("name", AGENT_NAMES)
def test_child_session_survives_other_selection(make_agent: MakeAgent, name: str) -> None:
    agent = make_agent(name)
    agent.reconcile(api_model(agent))
    _, _, parent = launch(agent)
    agent.reconcile(default(agent))
    if name == "claude":
        cmux = ["--settings", '{"hooks":{}}']
    else:
        cmux = ["-c", "hooks.example=true", "exec", "-m", "child-model", "hello"]
    with patch.dict(os.environ, parent, clear=True):
        _, argv, env = launch(agent, cmux)
    assert SECRET in env.values()
    if name == "claude":
        assert argv.count("--settings") == 1
        injected = json.loads(argv[argv.index("--settings") + 1])
        assert injected["hooks"] == {}
        assert injected["env"]["ANTHROPIC_BASE_URL"] == "https://test.invalid"
        assert env["ANTHROPIC_MODEL"] == "model"
    else:
        assert argv[-len(cmux) :] == cmux
        assert 'model="model"' in argv
        overrides = [argv[index + 1] for index, arg in enumerate(argv) if arg == "-c"]
        for override in overrides:
            tomlkit.parse(override)


def test_codex_keeps_comments_and_unrelated_settings(make_agent: MakeAgent) -> None:
    agent = make_agent("codex")
    agent.root.mkdir()
    user_config = [
        "# keep this",
        'model = "user-model"',
        "[features]",
        "user_feature = true",
        "[mcp_servers.user]",
        'command = "mine"',
    ]
    agent.config_file.write_text("\n".join(user_config) + "\n")
    agent.reconcile()
    assert "# keep this" in agent.config_file.read_text()
    agent.manifest["mcpServers"] = {}
    agent.reconcile()
    doc = read_document(agent.config_file)
    assert doc["model"] == "user-model"
    assert doc["mcp_servers"] == {"user": {"command": "mine"}}


def test_claude_keeps_hooks_and_user_permissions(make_agent: MakeAgent) -> None:
    agent = make_agent("claude")
    agent.root.mkdir()
    agent.config_file.write_text(
        json.dumps({"hooks": {"Stop": []}, "permissions": {"allow": ["user-rule"]}})
    )
    agent.manifest["maintainedSettings"] = {"permissions": {"allow": ["Read(/nix/store/**)"]}}
    agent.reconcile(api_model(agent))
    doc = read_document(agent.config_file)
    assert doc["hooks"] == {"Stop": []}
    assert doc["permissions"] == {"allow": ["user-rule", "Read(/nix/store/**)"]}


def test_claude_merges_caller_and_cmux_settings(make_agent: MakeAgent, home: Path) -> None:
    agent = make_agent("claude")
    agent.reconcile(api_model(agent))
    hooks = home / "cmux.json"
    hooks.write_text(
        json.dumps(
            {
                "hooks": {"Stop": [{"hooks": [{"command": "cmux hook"}]}]},
                "env": {"CALLER_VAR": "keep"},
            }
        )
    )
    args = [
        "--session-id",
        "fixture",
        "--settings",
        str(hooks),
        '--settings={"model":"explicit"}',
        "--",
        "--settings",
        "literal",
    ]
    _, argv, _ = launch(agent, args)
    settings = json.loads(argv[2])
    assert settings["model"] == "explicit"
    assert settings["env"]["CALLER_VAR"] == "keep"
    assert settings["hooks"]["Stop"][0]["hooks"][0]["command"] == "cmux hook"
    assert argv[-3:] == ["--", "--settings", "literal"]
    assert "hooks" not in read_document(agent.config_file)


def test_claude_custom_config_directory(make_agent: MakeAgent, home: Path) -> None:
    custom = home / "elsewhere"
    with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": str(custom)}):
        make_agent("claude").reconcile()
    assert (custom / "settings.json").exists()
    assert (custom / ".claude.json").exists()


def test_claude_fusion_picks_role_models(secret: Path) -> None:
    candidates = [
        model_entry("claude", secret, "api/large", "large"),
        model_entry("claude", secret, "api/small", "small"),
    ]
    fusion: Entry = {
        "label": "fusion",
        "fusion": {
            "roles": [
                {"name": "opus", "prompt": "OPUS model", "export": "ANTHROPIC_DEFAULT_OPUS_MODEL"}
            ],
            "candidates": candidates,
        },
    }
    agent = create_agent(manifest("claude", [fusion]))
    with patch.object(agent, "pick", side_effect=["fusion", "api/large", "api/small"]):
        entry = agent.choose()
    assert entry.get("env", {}) == {
        "ANTHROPIC_MODEL": "large",
        "ANTHROPIC_BASE_URL": "https://test.invalid",
        "CLAUDE_CODE_SUBAGENT_MODEL": "large",
        "CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT": "1",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "small",
    }
    agent.reconcile(entry)
    _, _, parent = launch(agent)
    with patch.dict(os.environ, parent, clear=True):
        _, _, env = launch(agent)
    assert env["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "small"


def test_malformed_config_is_not_overwritten(make_agent: MakeAgent) -> None:
    agent = make_agent("claude")
    agent.root.mkdir()
    agent.config_file.write_text("not json")
    with pytest.raises(ValueError):
        agent.reconcile()
    assert agent.config_file.read_text() == "not json"


def test_cancel_and_non_terminal_do_not_write(make_agent: MakeAgent) -> None:
    agent = make_agent("codex")
    with (
        terminal(),
        patch.object(agent, "choose", side_effect=KeyboardInterrupt),
        pytest.raises(KeyboardInterrupt),
    ):
        agent.select("/fake/launcher", [])
    assert not agent.state_file.exists()
    with patch.object(sys.stdin, "isatty", return_value=False), pytest.raises(SettingsError):
        agent.select("/fake/launcher", [])


def test_invalid_secret_does_not_save(make_agent: MakeAgent, secret: Path) -> None:
    agent = make_agent("codex")
    secret.write_text("bad\nembedded\n")
    with (
        terminal(),
        patch.object(agent, "choose", return_value=api_model(agent)),
        pytest.raises(SettingsError),
    ):
        agent.select("/fake/launcher", [])
    assert not agent.state_file.exists()


def test_selector_routes_through_cmux_after_save(make_agent: MakeAgent, home: Path) -> None:
    agent = make_agent("codex")
    integration = home / "cmux" / "shell-integration"
    wrapper = integration.parent / "bin" / "cmux-codex-wrapper"
    wrapper.parent.mkdir(parents=True)
    wrapper.write_text("#!/bin/sh\n")
    wrapper.chmod(0o755)
    cmux_env = {"CMUX_SURFACE_ID": "fixture", "CMUX_SHELL_INTEGRATION_DIR": str(integration)}
    with (
        patch.dict(os.environ, cmux_env),
        patch.object(sys, "platform", "darwin"),
        terminal(),
        patch.object(agent, "choose", return_value=api_model(agent)),
        patch.object(os, "execv", side_effect=SystemExit) as execute,
    ):
        with pytest.raises(SystemExit):
            agent.select("/fake/launcher", ["resume", "--last"])
        assert os.environ["CMUX_CUSTOM_CODEX_PATH"] == "/fake/launcher"
    assert execute.call_args.args == (str(wrapper), [str(wrapper), "resume", "--last"])
    assert read_document(agent.config_file)["model"] == "model"
