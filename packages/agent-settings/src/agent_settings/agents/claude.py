"""Claude Code: JSON settings whose `env` block routes provider and model."""

import copy
import json
from pathlib import Path
from typing import cast, final, override

from agent_settings.agents.base import Agent, Session
from agent_settings.catalog import Entry, Fusion
from agent_settings.documents import (
    Table,
    child_table,
    is_list,
    is_table,
    read_document,
)
from agent_settings.errors import SettingsError

_BASE_URL = "ANTHROPIC_BASE_URL"
_MODEL = "ANTHROPIC_MODEL"
_HEADERS = "ANTHROPIC_CUSTOM_HEADERS"
_SUBAGENT_MODEL = "CLAUDE_CODE_SUBAGENT_MODEL"
_ALLOW_UNKNOWN_MODELS = "CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT"

# Credentials Claude may carry from its own login; never saved or pinned.
_CREDENTIAL_ENV = frozenset({"ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", _HEADERS})


@final
class ClaudeAgent(Agent):
    name = "claude"
    home_env = "CLAUDE_CONFIG_DIR"
    config_name = "settings.json"
    extra_managed_env = frozenset({_HEADERS, _SUBAGENT_MODEL, _ALLOW_UNKNOWN_MODELS})

    @property
    def routing_env(self) -> set[str]:
        """Managed variables that route requests without being credentials."""
        return self.managed_env - self.catalog.secret_env() - _CREDENTIAL_ENV

    @override
    def apply_selection(self, doc: Table, selection: Entry) -> None:
        env = child_table(doc, "env")
        for key in self.managed_env:
            env.pop(key, None)
        values = dict(selection.get("env", {}))
        model = values.pop(_MODEL, None)
        doc.pop("model", None)
        if model:
            doc["model"] = model
        env.update(values)

    @override
    def extra_owned_documents(self) -> dict[str, tuple[Path, Table]]:
        # Claude's user MCP registry is separate from settings.json.
        return {"ownedMcp": (self._mcp_registry(), {"mcpServers": self.manifest["mcpServers"]})}

    @override
    def refine_choice(self, entry: Entry) -> Entry:
        return self._resolve_fusion(entry["fusion"]) if "fusion" in entry else entry

    def _resolve_fusion(self, fusion: Fusion) -> Entry:
        """Pick the main model, then one model per role from the same provider."""
        candidates = fusion["candidates"]
        main = self.pick([c["label"] for c in candidates], "main model")
        entry = copy.deepcopy(next(c for c in candidates if c["label"] == main))
        provider, model = main.split("/", 1)
        labels = [c["label"] for c in candidates if c["label"].startswith(f"{provider}/")]
        env = entry.setdefault("env", {})
        env.update({_SUBAGENT_MODEL: model, _ALLOW_UNKNOWN_MODELS: "1"})
        for role in fusion["roles"]:
            env[role["export"]] = self.pick(labels, role["prompt"]).split("/", 1)[1]
        return entry

    @override
    def load_credentials(self, entry: Entry, env: dict[str, str]) -> None:
        super().load_credentials(entry, env)
        headers = entry.get("secretHeaders")
        if headers:
            env[_HEADERS] = "\n".join(f"{header}: {env[key]}" for header, key in headers.items())

    @override
    def snapshot(self) -> Session:
        doc = read_document(self.config_file)
        selection = read_document(self.state_file).get("selection")
        routing_env = self.routing_env
        # settings.json stores env values and the model as strings.
        saved_env = cast(dict[str, str], doc.get("env", {}))
        env = {key: value for key, value in saved_env.items() if key in routing_env}
        if "model" in doc:
            env[_MODEL] = cast(str, doc["model"])
        entry = self.catalog.find(selection)
        # A hand-edited endpoint no longer matches the selected credentials.
        if entry is not None and env.get(_BASE_URL) != entry.get("env", {}).get(_BASE_URL):
            entry = None
        label = entry["label"] if entry is not None else None
        return Session(root=str(self.root), label=label, env=env, settings={})

    @override
    def launch_args(self, session: Session, args: list[str], *, inherited: bool) -> list[str]:
        if not session.get("label"):
            return args
        # Claude hot-reloads saved env, which also beats shell exports. Pin this
        # session's routing so another selector cannot redirect its loaded key.
        env = dict.fromkeys(self.routing_env, "") | session["env"]
        settings: Table = {"env": env, "model": session["env"].get(_MODEL, "")}
        # One --settings document is required: duplicate flags can discard
        # cmux's injected hooks entirely.
        caller_settings, forwarded = _split_settings_args(args)
        for source in caller_settings:
            _overlay(settings, source)
        return ["--settings", json.dumps(settings), *forwarded]

    def _mcp_registry(self) -> Path:
        if self.root != Path.home() / ".claude":
            return self.root / ".claude.json"
        return Path.home() / ".claude.json"


def _split_settings_args(args: list[str]) -> tuple[list[Table], list[str]]:
    """Separate caller `--settings` documents from the arguments to forward."""
    sources: list[Table] = []
    forwarded: list[str] = []
    remaining = iter(args)
    for arg in remaining:
        if arg == "--":
            forwarded += [arg, *remaining]
            break
        if arg == "--settings":
            value = next(remaining, None)
            if value is None:
                forwarded.append(arg)
            else:
                sources.append(_load_settings(value))
        elif arg.startswith("--settings="):
            sources.append(_load_settings(arg.partition("=")[2]))
        else:
            forwarded.append(arg)
    return sources, forwarded


def _load_settings(value: str) -> Table:
    """Parse a `--settings` value, which is inline JSON or a file path."""
    if value.lstrip().startswith("{"):
        source = cast(object, json.loads(value))
    elif Path(value).is_file():
        source = read_document(Path(value))
    else:
        raise SettingsError("inherited launch: settings file does not exist")
    if not is_table(source):
        raise SettingsError("inherited launch: expected a settings object")
    return source


def _overlay(target: Table, source: Table) -> None:
    """Merge `source` over `target`: tables recurse, lists extend, others replace."""
    for key, value in source.items():
        current = target.get(key)
        if is_table(value) and is_table(current):
            _overlay(current, value)
        elif is_list(value) and is_list(current):
            current.extend(value)
        else:
            target[key] = value
