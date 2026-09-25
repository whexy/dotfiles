import json
import os
from collections.abc import Callable
from pathlib import Path
from unittest.mock import patch

import pytest
from support import AGENT_NAMES, launch, terminal

from agent_settings.agents import Agent
from agent_settings.documents import read_document
from agent_settings.errors import SettingsError
from agent_settings.picker import SWITCH
from agent_settings.profiles import Profiles

type MakeAgent = Callable[[str], Agent]


@pytest.mark.parametrize("name", AGENT_NAMES)
def test_fork_settings_and_follow_managed_links(
    make_agent: MakeAgent, name: str, home: Path
) -> None:
    agent = make_agent(name)
    agent.reconcile(agent.catalog.choices[1])
    instruction = "CLAUDE.md" if name == "claude" else "AGENTS.md"
    generation = home / "generation-1"
    generation.write_text("old instructions")
    (agent.root / instruction).symlink_to(generation)
    (agent.root / "auth.json").write_text("private credentials")
    (agent.root / "history.jsonl").write_text("private history")
    skills = agent.root / "skills"
    skills.mkdir()
    (skills / "first").symlink_to(generation)
    root = Profiles(name).fork(agent.root, "secondary", [instruction, "skills"])
    assert read_document(root / agent.config_name) == read_document(agent.config_file)
    assert not (root / agent.config_name).is_symlink()
    assert not (root / "auth.json").exists()
    assert not (root / "history.jsonl").exists()
    generation2 = home / "generation-2"
    generation2.write_text("new instructions")
    (agent.root / instruction).unlink()
    (agent.root / instruction).symlink_to(generation2)
    (skills / "new").symlink_to(generation2)
    assert (root / instruction).read_text() == "new instructions"
    assert (root / "skills/new").read_text() == "new instructions"
    agent.set_root(root)
    agent.reconcile(agent.catalog.choices[0])
    assert read_document(Profiles(name).default / agent.config_name)["model"] == "model"


def test_claude_fork_copies_only_mcp_registry(make_agent: MakeAgent, home: Path) -> None:
    agent = make_agent("claude")
    agent.reconcile()
    (home / ".claude.json").write_text(
        json.dumps({"mcpServers": {"custom": {}}, "oauth": "secret"})
    )
    root = Profiles("claude").fork(agent.root, "second", [])
    assert read_document(root / ".claude.json") == {"mcpServers": {"custom": {}}}


@pytest.mark.parametrize("name", AGENT_NAMES)
def test_sync_ignores_override_and_updates_forks(
    make_agent: MakeAgent, home: Path, name: str
) -> None:
    agent = make_agent(name)
    agent.reconcile(agent.catalog.choices[1])
    profiles = Profiles(name)
    fork = profiles.fork(agent.root, "second", [])
    agent.manifest["mcpServers"] = {"owned": {"command": "/updated/server"}}
    external = home / "external"
    with patch.dict(os.environ, {agent.home_env: str(external)}):
        agent.set_root(external)
        agent.sync()
    assert not external.exists()
    for root in (profiles.default, fork):
        doc = (
            read_document(root / "config.toml")
            if name == "codex"
            else read_document(
                home / ".claude.json" if root == profiles.default else root / ".claude.json"
            )
        )
        key = "mcp_servers" if name == "codex" else "mcpServers"
        assert doc[key] == {"owned": {"command": "/updated/server"}}
        assert read_document(root / agent.config_name)["model"] == "model"


@pytest.mark.parametrize("name", AGENT_NAMES)
def test_switch_is_per_launch_and_children_keep_root(make_agent: MakeAgent, name: str) -> None:
    agent = make_agent(name)
    agent.reconcile()
    root = Profiles(name).fork(agent.root, "second", [])
    with (
        terminal(),
        patch.object(agent, "pick", side_effect=[SWITCH, "api/model"]),
        patch("agent_settings.agents.base.pick", return_value="second"),
        patch.object(os, "execv", side_effect=SystemExit),
        patch.dict(os.environ),
    ):
        with pytest.raises(SystemExit):
            agent.select("/fake/launcher", [])
        assert os.environ[agent.home_env] == str(root)
        child = make_agent(name)
        _, _, env = launch(child)
        assert child.root == root
        assert env[agent.home_env] == str(root)
    assert make_agent(name).root == Profiles(name).default


def test_delete_protects_default_external_and_symlinks(home: Path) -> None:
    profiles = Profiles("codex")
    profiles.default.mkdir()
    target = profiles.fork(profiles.default, "second", [])
    outside = home / "outside"
    outside.mkdir()
    linked = profiles.directory / "linked"
    linked.symlink_to(outside)
    for root in (profiles.default, outside, linked):
        with pytest.raises(SettingsError):
            profiles.delete(root)
    profiles.delete(target)
    assert not target.exists()
    assert outside.exists()


@pytest.mark.parametrize("name", ["default", "../escape", "", ".hidden", "a/b"])
def test_invalid_fork_names(home: Path, name: str) -> None:
    assert Path.home() == home
    profiles = Profiles("codex")
    with pytest.raises(SettingsError):
        profiles.fork(profiles.default, name, [])


def test_fork_of_fork_survives_source_deletion(make_agent: MakeAgent, home: Path) -> None:
    agent = make_agent("claude")
    agent.reconcile()
    (agent.root / "CLAUDE.md").write_text("shared")
    profiles = Profiles("claude")
    first = profiles.fork(agent.root, "first", ["CLAUDE.md"])
    second = profiles.fork(first, "second", ["CLAUDE.md"])
    profiles.delete(first)
    assert (second / "CLAUDE.md").read_text() == "shared"
    assert (second / "CLAUDE.md").readlink() == home / ".claude/CLAUDE.md"


def test_fork_external_instructions_are_preserved(home: Path) -> None:
    source = home / "external"
    source.mkdir()
    (source / "AGENTS.md").write_text("external instructions")
    root = Profiles("codex").fork(source, "external-copy", ["AGENTS.md"])
    assert (root / "AGENTS.md").read_text() == "external instructions"
    assert not (root / "AGENTS.md").is_symlink()


def test_duplicate_fork_leaves_original_intact(home: Path) -> None:
    profiles = Profiles("codex")
    root = profiles.fork(home, "second", [])
    (root / "sentinel").write_text("keep")
    with pytest.raises(SettingsError, match="already exists"):
        profiles.fork(home, "second", [])
    assert (root / "sentinel").read_text() == "keep"
