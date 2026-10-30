"""The selector catalog that `withModelPicker.nix` writes for each agent."""

import copy
from collections.abc import Callable
from dataclasses import dataclass
from typing import NotRequired, Self, TypedDict

from agent_settings.documents import Table


class Role(TypedDict):
    """A fusion role, filled by its own pick among the main model's provider."""

    name: str
    prompt: str
    export: str


class Fusion(TypedDict):
    roles: list[Role]
    candidates: list["Entry"]


class Discover(TypedDict):
    """Stand for one entry per model a live model list serves."""

    url: str
    """A Codex model catalog endpoint (`/v1/models?client_version=...`), or
    an OpenAI model list (`/v1/models`) when `owner` is set."""
    keyEnv: str
    """Secret variable holding the bearer token for `url`."""
    modelEnv: list[str]
    """Variables that receive the model ID."""
    owner: NotRequired[str]
    """Keep only the models of this upstream route (`owned_by`), which only
    the OpenAI model list names."""


class Entry(TypedDict):
    label: str
    display: NotRequired[str]
    """Picker text when it differs from the label; discovery puts the model's
    display name here while the label keeps the model ID, so saved selections
    stay resolvable regardless of naming changes."""
    env: NotRequired[dict[str, str]]
    """Nonsecret environment, saved into the agent's native settings."""
    secrets: NotRequired[dict[str, str]]
    """Environment variable to credential file, read only at launch."""
    secretHeaders: NotRequired[dict[str, str]]
    """HTTP header to the secret environment variable holding its value."""
    settings: NotRequired[Table]
    """Native configuration keys, saved into the agent's settings."""
    fusion: NotRequired[Fusion]
    discover: NotRequired[Discover]


class Manifest(TypedDict):
    name: str
    real: str
    """The wrapped agent executable."""
    managedLinks: NotRequired[list[str]]
    entries: list[Entry]
    resetEnv: list[str]
    """Provider variables cleared whenever a selection is active."""
    mcpServers: Table
    maintainedSettings: Table


def model_entry(template: Entry, model: str, name: str | None = None) -> Entry:
    """The entry a discovery template stands for when it serves `model`."""
    entry = copy.deepcopy(template)
    discover = entry.pop("discover")
    entry["label"] = f"{template['label']}/{model}"
    if name is not None and name != model:
        entry["display"] = f"{template['label']} · {name} · {model}"
    entry["env"] = entry.get("env", {}) | dict.fromkeys(discover["modelEnv"], model)
    return entry


@dataclass(frozen=True)
class Catalog:
    choices: list[Entry]
    """Entries offered by the first picker."""
    entries: list[Entry]
    """Every selectable entry, fusion candidates included."""

    @classmethod
    def from_choices(cls, choices: list[Entry]) -> Self:
        candidates = [
            candidate
            for entry in choices
            if "fusion" in entry
            for candidate in entry["fusion"]["candidates"]
        ]
        return cls(choices, choices + candidates)

    def find(self, label: object) -> Entry | None:
        """Look up an entry, rebuilding discovered models without the network.

        A saved discovered model stays selected while its service is
        unreachable; the service rejects it once it is no longer served.
        """
        for entry in self.entries:
            if entry["label"] == label:
                return entry
        for entry in self.entries:
            prefix = f"{entry['label']}/"
            if "discover" in entry and isinstance(label, str) and label.startswith(prefix):
                return model_entry(entry, label.removeprefix(prefix))
        return None

    def secret_env(self) -> set[str]:
        return {key for entry in self.entries for key in entry.get("secrets", {})}

    def provided_env(self) -> set[str]:
        """Every variable that some selection sets."""
        keys = self.secret_env()
        for entry in self.entries:
            keys.update(entry.get("env", {}))
            if "fusion" in entry:
                keys.update(role["export"] for role in entry["fusion"]["roles"])
            if "discover" in entry:
                keys.update(entry["discover"]["modelEnv"])
        return keys


def expand(
    entries: list[Entry], served: Callable[[Entry, Discover], list[tuple[str, str]]]
) -> list[Entry]:
    """Replace each discovery template with an entry per served model."""
    expanded: list[Entry] = []
    for entry in entries:
        discover = entry.get("discover")
        if discover is None:
            expanded.append(entry)
        else:
            expanded += [model_entry(entry, model, name) for model, name in served(entry, discover)]
    return expanded
