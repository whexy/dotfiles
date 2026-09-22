"""Codex: TOML config whose top-level keys choose a model provider."""

from typing import final, override

import tomlkit

from agent_settings.agents.base import Agent, Session
from agent_settings.catalog import Entry
from agent_settings.documents import Table, child_table, is_table, read_document, table_or_empty

# Top-level keys a selection owns; any of them left over would override it.
_SELECTION_KEYS = ("model", "model_provider", "profile", "preferred_auth_method")


@final
class CodexAgent(Agent):
    name = "codex"
    home_env = "CODEX_HOME"
    config_name = "config.toml"

    @override
    def maintained_settings(self) -> Table:
        # Every provider stays defined so saved selections keep resolving.
        desired = super().maintained_settings()
        providers = child_table(desired, "model_providers")
        for entry in self.catalog.choices:
            providers.update(table_or_empty(entry.get("settings", {}).get("model_providers")))
        desired["mcp_servers"] = self.manifest["mcpServers"]
        return desired

    @override
    def apply_selection(self, doc: Table, selection: Entry) -> None:
        for key in _SELECTION_KEYS:
            doc.pop(key, None)
        settings = selection.get("settings", {})
        doc.update({key: value for key, value in settings.items() if key != "model_providers"})

    @override
    def snapshot(self) -> Session:
        doc = read_document(self.config_file)
        selection = read_document(self.state_file).get("selection")
        provider = doc.get("model_provider", "openai")
        settings: Table = {"model_provider": provider}
        if "model" in doc:
            settings["model"] = doc["model"]
        entry = next((e for e in self.catalog.entries if _provider(e) == provider), None)
        if entry is not None:
            settings["model_providers"] = entry.get("settings", {})["model_providers"]
        elif provider == "openai" and selection:
            # The native ChatGPT login is the entry without provider settings.
            entry = next((e for e in self.catalog.entries if "settings" not in e), None)
        label = entry["label"] if entry is not None else None
        return Session(root=str(self.root), label=label, env={}, settings=settings)

    @override
    def launch_args(self, session: Session, args: list[str], *, inherited: bool) -> list[str]:
        if not inherited:
            return args
        # Saved defaults come first, so a dedicated --model and later -c
        # arguments from cmux or the caller still win and are never persisted.
        overrides = [
            arg
            for key, value in session["settings"].items()
            for arg in ("-c", f"{key}={_toml_value(value)}")
        ]
        return [*overrides, *args]


def _provider(entry: Entry) -> object:
    return entry.get("settings", {}).get("model_provider")


def _toml_value(value: object) -> str:
    """Encode a value as the TOML expression of a `-c key=value` override."""
    # tomlkit annotates its API with bare generics. item() would render a
    # dict as a multi-line table, so tables are built inline explicitly.
    if is_table(value):
        table = tomlkit.inline_table()
        table.update(value)  # pyright: ignore[reportUnknownMemberType]
        return table.as_string()
    return tomlkit.item(value).as_string()  # pyright: ignore[reportCallIssue, reportArgumentType, reportUnknownMemberType, reportUnknownVariableType]
