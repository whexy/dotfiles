from agent_settings.agents.base import Agent, Session
from agent_settings.agents.claude import ClaudeAgent
from agent_settings.agents.codex import CodexAgent
from agent_settings.agents.muse import MuseAgent
from agent_settings.catalog import Manifest
from agent_settings.errors import SettingsError

__all__ = ["Agent", "ClaudeAgent", "CodexAgent", "MuseAgent", "Session", "create_agent"]

_AGENTS: dict[str, type[Agent]] = {
    agent.name: agent for agent in (ClaudeAgent, CodexAgent, MuseAgent)
}


def create_agent(manifest: Manifest) -> Agent:
    agent = _AGENTS.get(manifest["name"])
    if agent is None:
        raise SettingsError(f"unsupported agent: {manifest['name']}")
    return agent(manifest)
