import json
import os
import re
import sys
from collections.abc import Callable
from pathlib import Path
from unittest.mock import patch

import pytest
import tomlkit
from support import AGENT_NAMES, SECRET, launch, manifest, model_entry, terminal

from agent_settings.agents import Agent, create_agent
from agent_settings.catalog import Entry
from agent_settings.documents import child_table, edit_document, read_document
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
def test_default_selection_removes_overrides_and_keeps_auth(
    make_agent: MakeAgent, name: str
) -> None:
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
        caller = ["--settings", '{"hooks":{}}']
    else:
        caller = ["-c", "hooks.example=true", "exec", "-m", "child-model", "hello"]
    with patch.dict(os.environ, parent, clear=True):
        _, argv, env = launch(agent, caller)
    assert SECRET in env.values()
    if name == "claude":
        assert argv.count("--settings") == 1
        injected = json.loads(argv[argv.index("--settings") + 1])
        assert injected["hooks"] == {}
        assert injected["env"]["ANTHROPIC_BASE_URL"] == "https://test.invalid"
        assert env["ANTHROPIC_MODEL"] == "model"
    else:
        assert argv[-len(caller) :] == caller
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


@pytest.mark.parametrize("explicit_model", [False, True])
def test_codex_proxy_discovery_tracks_selection(
    make_agent: MakeAgent, explicit_model: bool
) -> None:
    agent = make_agent("codex")
    entry = api_model(agent)
    settings = entry.setdefault("settings", {})
    settings["features"] = {"api_key_model_discovery": True}
    child_table(child_table(settings, "model_providers"), "dotfiles-test")["model_catalog_url"] = (
        "https://test.invalid/v1/models?client_version=0.158.0"
    )
    if not explicit_model:
        settings.pop("model")
    agent.root.mkdir()
    agent.config_file.write_text("[features]\nuser_feature = true\n")
    agent.reconcile(entry)
    agent.reconcile()
    doc = read_document(agent.config_file)
    assert doc["features"] == {"user_feature": True, "api_key_model_discovery": True}
    provider = child_table(child_table(doc, "model_providers"), "dotfiles-test")
    assert provider["model_catalog_url"] == (
        "https://test.invalid/v1/models?client_version=0.158.0"
    )
    _, _, parent = launch(agent)
    agent.reconcile(default(agent))
    agent.reconcile()
    assert read_document(agent.config_file)["features"] == {"user_feature": True}
    with patch.dict(os.environ, parent, clear=True):
        _, argv, _ = launch(agent)
    overrides = [tomlkit.parse(argv[i + 1]) for i, arg in enumerate(argv) if arg == "-c"]
    assert any(d.get("features", {}).get("api_key_model_discovery") is True for d in overrides)


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


def test_claude_merges_caller_settings(make_agent: MakeAgent, home: Path) -> None:
    agent = make_agent("claude")
    agent.reconcile(api_model(agent))
    hooks = home / "caller.json"
    hooks.write_text(
        json.dumps(
            {
                "hooks": {"Stop": [{"hooks": [{"command": "caller hook"}]}]},
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
    assert settings["hooks"]["Stop"][0]["hooks"][0]["command"] == "caller hook"
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


def discovered(secret: Path) -> Entry:
    return {
        "label": "proxy",
        "secrets": {"ANTHROPIC_API_KEY": str(secret)},
        "env": {"ANTHROPIC_BASE_URL": "https://test.invalid"},
        "discover": {
            "url": "https://test.invalid/v1/models",
            "keyEnv": "ANTHROPIC_API_KEY",
            "modelEnv": ["ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL"],
        },
    }


def test_claude_discovered_model_fills_roles_and_survives_sync(secret: Path) -> None:
    agent = create_agent(manifest("claude", [discovered(secret)]))
    with (
        patch.object(agent, "served_models", return_value=["vendor/a", "b"]),
        patch.object(agent, "pick", return_value="proxy/vendor/a") as pick,
    ):
        entry = agent.choose()
    assert pick.call_args.args[0] == ["default", "proxy/vendor/a", "proxy/b"]
    assert entry.get("env", {}) == {
        "ANTHROPIC_BASE_URL": "https://test.invalid",
        "ANTHROPIC_MODEL": "vendor/a",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "vendor/a",
    }
    agent.reconcile(entry)
    # Activation rebuilds the saved model offline instead of resetting it.
    with patch.object(agent, "served_models", side_effect=AssertionError):
        agent.sync()
    doc = read_document(agent.config_file)
    assert doc["model"] == "vendor/a"
    assert child_table(doc, "env")["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "vendor/a"
    _, _, env = launch(agent)
    assert env["ANTHROPIC_API_KEY"] == SECRET


def test_unreachable_model_list_offers_the_saved_model(secret: Path) -> None:
    agent = create_agent(manifest("claude", [discovered(secret)]))
    saved = agent.catalog.find("proxy/vendor/a")
    assert saved is not None
    agent.reconcile(saved)
    down = SettingsError("proxy: model discovery failed: connection refused")
    with (
        patch.object(agent, "served_models", side_effect=down),
        patch.object(agent, "pick", return_value="proxy/vendor/a") as pick,
    ):
        entry = agent.choose()
    labels, prompt = pick.call_args.args
    assert labels == ["proxy/vendor/a", "default"]
    assert "connection refused" in prompt
    assert entry.get("env", {})["ANTHROPIC_MODEL"] == "vendor/a"


def test_claude_fusion_picks_discovered_role_models_and_survives_sync(secret: Path) -> None:
    fusion: Entry = {
        "label": "fusion",
        "fusion": {
            "roles": [
                {"name": "opus", "prompt": "OPUS model", "export": "ANTHROPIC_DEFAULT_OPUS_MODEL"}
            ],
            "candidates": [discovered(secret)],
        },
    }
    agent = create_agent(manifest("claude", [fusion]))
    with (
        patch.object(agent, "served_models", return_value=["large", "small"]),
        patch.object(agent, "pick", side_effect=["fusion", "proxy/large", "proxy/small"]),
    ):
        entry = agent.choose()
    env = entry.get("env", {})
    assert env["ANTHROPIC_MODEL"] == "large"
    assert env["CLAUDE_CODE_SUBAGENT_MODEL"] == "large"
    assert env["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "small"
    agent.reconcile(entry)
    agent.sync()
    saved = child_table(read_document(agent.config_file), "env")
    assert saved["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "small"
    assert saved["CLAUDE_CODE_SUBAGENT_MODEL"] == "large"


def test_codex_in_app_model_and_profile_survive_sync(make_agent: MakeAgent) -> None:
    agent = make_agent("codex")
    agent.reconcile(default(agent))
    # Codex's /model picker and the user edit the saved config directly.
    with edit_document(agent.config_file) as doc:
        doc["model"] = "picked"
        doc["profile"] = "work"
    agent.sync()
    doc = read_document(agent.config_file)
    assert doc["model"] == "picked"
    assert doc["profile"] == "work"


@pytest.mark.parametrize("name", AGENT_NAMES)
def test_malformed_config_is_named_and_not_overwritten(make_agent: MakeAgent, name: str) -> None:
    agent = make_agent(name)
    agent.root.mkdir()
    agent.config_file.write_text("not = [valid")
    with pytest.raises(SettingsError, match=re.escape(str(agent.config_file))):
        agent.reconcile()
    assert agent.config_file.read_text() == "not = [valid"


def test_failed_first_selection_never_routes_without_credentials(
    make_agent: MakeAgent, home: Path
) -> None:
    agent = make_agent("claude")
    (home / ".claude.json").write_text("not json")
    with pytest.raises(SettingsError, match=re.escape(str(home / ".claude.json"))):
        agent.reconcile(api_model(agent))
    _, _, env = launch(agent)
    if "ANTHROPIC_BASE_URL" in child_table(read_document(agent.config_file), "env"):
        assert env["ANTHROPIC_API_KEY"] == SECRET


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
