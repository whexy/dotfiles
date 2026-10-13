"""Muse Code: JSON settings whose top-level keys choose model and endpoint."""

import json
import os
from collections.abc import MutableMapping
from pathlib import Path
from typing import cast, final, override

from agent_settings.agents.base import Agent, Session
from agent_settings.catalog import Entry
from agent_settings.documents import Table, read_document, table_or_empty
from agent_settings.profiles import muse_config_home

_MODEL_ENV = "MUSE_MODEL"
_ENDPOINT = "endpoint_transport"


@final
class MuseAgent(Agent):
    name = "muse"
    home_env = "XDG_CONFIG_HOME"
    config_name = "settings.json"
    config_subdir = "muse"
    extra_managed_env = frozenset({_MODEL_ENV})

    @override
    def default_root(self) -> Path:
        return muse_config_home().absolute() / "muse"

    @override
    def initial_root(self) -> Path:
        # Unlike the default, this follows a named config's exported
        # XDG_CONFIG_HOME: it is where this launch's config actually lives.
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        return config_home.expanduser().absolute() / "muse"

    @override
    def export_root(self, env: MutableMapping[str, str]) -> None:
        # Muse finds its config under $XDG_CONFIG_HOME/muse, so a named
        # config is exported as an XDG config home of its own.
        if self.root == self.default_root():
            env.pop(self.home_env, None)
        else:
            env[self.home_env] = str(self.root.parent)

    @override
    def maintained_settings(self, _selection: Entry | None = None) -> Table:
        desired = super().maintained_settings(_selection)
        desired["mcpServers"] = self.manifest["mcpServers"]
        return desired

    @override
    def apply_selection(self, doc: Table, selection: Entry) -> None:
        doc.pop("model", None)
        doc.pop(_ENDPOINT, None)
        settings = selection.get("settings", {})
        doc.update(settings)
        model = selection.get("env", {}).get(_MODEL_ENV)
        if model:
            doc["model"] = model

    @override
    def snapshot(self) -> Session:
        doc = read_document(self.config_file)
        state = read_document(self.state_file).get("selection")
        entry = self.catalog.find(state)
        settings: Table = {}
        endpoint = table_or_empty(doc.get(_ENDPOINT))
        if endpoint:
            settings[_ENDPOINT] = endpoint
        if "model" in doc:
            settings["model"] = doc["model"]
        if entry is not None:
            expected = table_or_empty(entry.get("settings", {}).get(_ENDPOINT))
            # A hand-edited endpoint no longer matches the selected credentials.
            if endpoint.get("base_url") != expected.get("base_url"):
                entry = None
        label = entry["label"] if entry is not None else None
        return Session(root=str(self.root), label=label, env={}, settings=settings)

    @override
    def launch_args(self, session: Session, args: list[str], *, inherited: bool) -> list[str]:
        if not inherited or not session.get("label"):
            return args
        # Saved defaults come first, so a dedicated --model and later -c
        # arguments from the caller still win and are never persisted.
        settings = session["settings"]
        overrides: list[str] = []
        if "model" in settings:
            overrides += ["-c", f"model={json.dumps(cast(str, settings['model']))}"]
        endpoint = table_or_empty(settings.get(_ENDPOINT))
        if endpoint.get("base_url"):
            overrides += [
                "-c",
                f"{_ENDPOINT}.base_url={json.dumps(cast(str, endpoint['base_url']))}",
            ]
        return [*overrides, *args]
