"""Muse Code: JSON settings whose top-level keys choose model and endpoint."""

import json
import os
import subprocess
import sys
from collections.abc import MutableMapping
from pathlib import Path
from typing import cast, final, override

from agent_settings.agents.base import Agent, Session
from agent_settings.catalog import Entry
from agent_settings.credentials import read_secrets
from agent_settings.documents import (
    Table,
    edit_document,
    is_list,
    is_table,
    read_document,
    table_or_empty,
)
from agent_settings.errors import SettingsError
from agent_settings.profiles import muse_config_home

_MODEL_ENV = "MUSE_MODEL"
_KEY_ENV = "META_API_KEY"
_ENDPOINT = "endpoint_transport"
_HEADERS = "http_headers"
# Muse's own provider rows always arrive hidden, so only rows declared in
# settings ever appear in /models; the catalog is rebuilt from the gateway's
# model list on every reconcile. Provider/profile must match the session's.
_PROVIDER_ID = "meta"
_PROFILE_ID = "tbh"
_CATALOG = "model_catalog"
# Muse takes root options before a prompt or `resume`, but only after these.
_OPTIONS_AFTER_COMMAND = frozenset({"exec", "serve"})
# Commands that start no model session, and reject root options anyway.
_SESSIONLESS_COMMANDS = frozenset(
    {
        "auth",
        "config",
        "export",
        "init",
        "login",
        "logout",
        "mcp",
        "model-profile",
        "plugins",
        "sandbox",
        "schema",
        "session-message",
        "skills",
        "trace",
        "usage",
        "voice",
        "workflows",
    }
)


@final
class MuseAgent(Agent):
    """Muse, whose credentials live in its own config rather than its environment.

    Its tools inherit the environment, so `reconcile` saves the selected
    endpoint's API key with `muse auth set` and its HTTP headers in
    `endpoint_transport`, and launches export neither.
    """

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
    def maintained_settings(self, selection: Entry | None = None) -> Table:
        desired = super().maintained_settings(selection)
        desired["mcpServers"] = self.manifest["mcpServers"]
        desired[_CATALOG] = self._catalog(selection)
        return desired

    @override
    def reconcile(self, selection: Entry | None = None) -> None:
        entry = selection
        if entry is None:
            entry = self.catalog.find(read_document(self.state_file).get("selection"))
            saved = table_or_empty(read_document(self.config_file).get(_ENDPOINT))
            # A selection saved for another gateway address keeps that
            # gateway's model and catalog, so it is applied again in full.
            if entry is not None and saved.get("base_url") != _base_url(entry):
                selection = entry
        # Read before saving, so a selection that cannot authenticate is never saved.
        secrets = read_secrets(entry.get("secrets", {})) if entry is not None else {}
        super().reconcile(selection)
        if entry is not None:
            self._save_credentials(entry, secrets)

    def _save_credentials(self, entry: Entry, secrets: dict[str, str]) -> None:
        # The endpoint follows the entry on every reconcile, so a changed
        # gateway address reaches saved selections, and its headers are only
        # ever sent to the origin they were issued for.
        endpoint = dict(table_or_empty(entry.get("settings", {}).get(_ENDPOINT)))
        headers = {header: secrets[env] for header, env in entry.get("secretHeaders", {}).items()}
        if headers:
            endpoint[_HEADERS] = headers
        with edit_document(self.state_file), edit_document(self.config_file) as doc:
            if endpoint:
                doc[_ENDPOINT] = endpoint
            else:
                doc.pop(_ENDPOINT, None)
        key = secrets.get(_KEY_ENV)
        if key is None:
            return
        # Muse picks the store itself (a file, or the macOS Keychain), so the
        # key goes through its CLI rather than into auth.json.
        env = os.environ.copy()
        env.pop(_KEY_ENV, None)
        self.export_root(env)
        try:
            subprocess.run(
                [self.manifest["real"], "auth", "set", "--api-key-stdin"],
                input=key,
                text=True,
                env=env,
                capture_output=True,
                check=True,
                timeout=60,
            )
        except subprocess.CalledProcessError as error:
            detail = cast(str, error.stderr).strip() or f"exit status {error.returncode}"
            raise SettingsError(f"muse auth set failed: {detail}") from error
        except subprocess.TimeoutExpired as error:
            raise SettingsError("muse auth set did not finish") from error

    @override
    def load_credentials(self, entry: Entry, env: dict[str, str]) -> None:
        """Leave the environment alone: Muse reads what `reconcile` saved."""

    def _effective_entry(self, selection: Entry | None) -> Entry | None:
        if selection is not None:
            return selection
        saved = read_document(self.state_file).get("selection")
        entry = self.catalog.find(saved)
        if entry is not None:
            return entry
        return self.catalog.choices[0] if self.catalog.choices else None

    def _current_model(self, entry: Entry | None) -> str | None:
        if entry is not None:
            model = entry.get("env", {}).get(_MODEL_ENV)
            if isinstance(model, str) and model:
                return model
            settings_model = table_or_empty(entry.get("settings")).get("model")
            if isinstance(settings_model, str) and settings_model:
                return settings_model
        doc_model = read_document(self.config_file).get("model")
        return doc_model if isinstance(doc_model, str) and doc_model else None

    def _catalog(self, selection: Entry | None) -> list[object]:
        entry = self._effective_entry(selection)
        template = next((e for e in self.manifest["entries"] if "discover" in e), None)
        if template is None:
            return []
        current = self._current_model(entry)
        saved = read_document(self.state_file).get("selection")
        entry_is_saved = entry is not None and saved is not None and entry.get("label") == saved
        # A sync without a new selection rebuilds the saved model offline
        # (catalog.find); only an explicit selection refreshes the catalog.
        if selection is None and entry_is_saved:
            previous = self._previous_catalog(current)
            if previous is not None:
                return previous
        try:
            models = self.served_models(template, template["discover"])
        except SettingsError as error:
            # A failed refresh keeps the catalog the last reconcile wrote.
            print(
                f"agent-settings: warning: {error}; keeping the saved model catalog",
                file=sys.stderr,
            )
            previous = self._previous_catalog(current)
            if previous is not None:
                return previous
            return [self._catalog_row(current, current, 0)] if current else []
        return [
            self._catalog_row(model, name, order, current=current)
            for order, (model, name) in enumerate(models)
        ]

    def _previous_catalog(self, current: str | None) -> list[object] | None:
        owned = table_or_empty(read_document(self.state_file).get("owned"))
        rows = owned.get(_CATALOG)
        if not is_list(rows) or not rows:
            return None
        # Restamp currency: the kept rows must not name a stale current model.
        kept: list[object] = []
        for row in rows:
            if not is_table(row):
                return None
            row = dict(row)
            row["is_current"] = row.get("model_id") == current
            if row.get("is_default") and not row["is_current"]:
                row["is_default"] = False
            kept.append(row)
        if current and all(table_or_empty(r).get("model_id") != current for r in kept):
            kept[0] = self._catalog_row(current, current, 0)
        return kept

    @staticmethod
    def _catalog_row(model: str, name: str, order: int, *, current: str | None = None) -> Table:
        # Default to this row when no current model is named, so the
        # catalog Muse composes always has a current row.
        row: Table = {
            "model_id": model,
            "display_label": name,
            "provider_id": _PROVIDER_ID,
            "profile_id": _PROFILE_ID,
            "visibility": "visible",
            "display_order": order,
        }
        if current is None or model == current:
            row["is_current"] = True
            row["is_default"] = True
        return row

    @override
    def apply_selection(self, doc: Table, selection: Entry) -> None:
        # The endpoint is written with its credentials (`_save_credentials`).
        doc.pop("model", None)
        settings = selection.get("settings", {})
        doc.update({key: value for key, value in settings.items() if key != _ENDPOINT})
        model = selection.get("env", {}).get(_MODEL_ENV)
        if model:
            doc["model"] = model

    @override
    def snapshot(self) -> Session:
        doc = read_document(self.config_file)
        state = read_document(self.state_file).get("selection")
        entry = self.catalog.find(state)
        settings: Table = {}
        # Sessions travel in the environment, so the headers stay behind.
        endpoint = {
            key: value
            for key, value in table_or_empty(doc.get(_ENDPOINT)).items()
            if key != _HEADERS
        }
        if endpoint:
            settings[_ENDPOINT] = endpoint
        if "model" in doc:
            settings["model"] = doc["model"]
        # A hand-edited endpoint no longer matches the selected credentials.
        if entry is not None and endpoint.get("base_url") != _base_url(entry):
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
        command = args[0] if args else None
        if command in _OPTIONS_AFTER_COMMAND:
            return [command, *overrides, *args[1:]]
        if command in _SESSIONLESS_COMMANDS:
            return args
        return [*overrides, *args]


def _base_url(entry: Entry) -> object:
    return table_or_empty(entry.get("settings", {}).get(_ENDPOINT)).get("base_url")
