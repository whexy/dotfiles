"""The selector catalog that `withModelPicker.nix` writes for each agent."""

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


class Entry(TypedDict):
    label: str
    env: NotRequired[dict[str, str]]
    """Nonsecret environment, saved into the agent's native settings."""
    secrets: NotRequired[dict[str, str]]
    """Environment variable to credential file, read only at launch."""
    secretHeaders: NotRequired[dict[str, str]]
    """HTTP header to the secret environment variable holding its value."""
    settings: NotRequired[Table]
    """Native configuration keys, saved into the agent's settings."""
    fusion: NotRequired[Fusion]


class Manifest(TypedDict):
    name: str
    real: str
    """The wrapped agent executable."""
    fzf: str
    entries: list[Entry]
    resetEnv: list[str]
    """Provider variables cleared whenever a selection is active."""
    mcpServers: Table
    maintainedSettings: Table


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
        return next((entry for entry in self.entries if entry["label"] == label), None)

    def secret_env(self) -> set[str]:
        return {key for entry in self.entries for key in entry.get("secrets", {})}

    def provided_env(self) -> set[str]:
        """Every variable that some selection sets."""
        keys = self.secret_env()
        for entry in self.entries:
            keys.update(entry.get("env", {}))
            if "fusion" in entry:
                keys.update(role["export"] for role in entry["fusion"]["roles"])
        return keys
