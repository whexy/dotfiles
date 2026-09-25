"""The select, sync, and launch flows every agent shares."""

import copy
import json
import os
import sys
from abc import ABC, abstractmethod
from collections.abc import MutableMapping
from pathlib import Path
from typing import ClassVar, NoReturn, TypedDict, cast

from agent_settings.catalog import Catalog, Entry, Manifest
from agent_settings.credentials import read_secrets
from agent_settings.documents import Table, edit_document, read_document, table_or_empty
from agent_settings.errors import SettingsError
from agent_settings.ownership import merge_owned
from agent_settings.picker import DELETE, FORK, SWITCH, ask, pick
from agent_settings.profiles import Profiles

_CMUX_INTEGRATION = "/Applications/cmux.app/Contents/Resources/shell-integration"


class Session(TypedDict):
    """Nonsecret launch defaults a running session hands to its descendants."""

    root: str
    label: str | None
    env: dict[str, str]
    settings: Table


class Agent(ABC):
    """One agent CLI whose native settings file stays writable.

    `dotfiles-settings.json` beside the native settings records what the last
    reconciliation owned (`owned`) and the selected entry label (`selection`).
    It never holds credential values.
    """

    name: ClassVar[str]
    home_env: ClassVar[str]
    """Variable that relocates the agent's configuration directory."""
    config_name: ClassVar[str]
    extra_managed_env: ClassVar[frozenset[str]] = frozenset()
    """Variables this agent's selection logic sets beyond the catalog's."""

    manifest: Manifest
    catalog: Catalog
    root: Path
    config_file: Path
    state_file: Path
    session_env: str
    managed_env: set[str]
    """Variables an active selection owns in the launch environment."""

    def __init__(self, manifest: Manifest) -> None:
        self.manifest = manifest
        self.catalog = Catalog.from_choices(manifest["entries"])
        default_root = Path.home() / f".{self.name}"
        self.root = Path(os.environ.get(self.home_env, default_root)).expanduser().absolute()
        self.set_root(self.root)
        self.session_env = f"DOTFILES_{self.name.upper()}_SESSION"
        self.managed_env = (
            set(manifest["resetEnv"]) | self.catalog.provided_env() | self.extra_managed_env
        )

    # Agent-specific steps.

    @abstractmethod
    def apply_selection(self, doc: Table, selection: Entry) -> None:
        """Replace the selection-owned fields of the native settings."""

    @abstractmethod
    def snapshot(self) -> Session:
        """Read the launch defaults currently saved in the native settings."""

    @abstractmethod
    def launch_args(self, session: Session, args: list[str], *, inherited: bool) -> list[str]:
        """Arguments that apply `session` ahead of the caller's own."""

    def maintained_settings(self) -> Table:
        return copy.deepcopy(self.manifest["maintainedSettings"])

    def extra_owned_documents(self) -> dict[str, tuple[Path, Table]]:
        """Other files Nix maintains values in, keyed by their ownership record."""
        return {}

    def refine_choice(self, entry: Entry) -> Entry:
        """Complete a picked entry, possibly by asking further questions."""
        return entry

    def load_credentials(self, entry: Entry, env: dict[str, str]) -> None:
        env.update(read_secrets(entry.get("secrets", {})))

    # Shared flows.

    def reconcile(self, selection: Entry | None = None) -> None:
        """Maintain Nix-owned settings and optionally save a new selection."""
        # Our multi-file writers serialize on the state lock. Each native file
        # also gets an optimistic check against non-cooperating writers.
        with edit_document(self.state_file) as state:
            desired = self.maintained_settings()
            with edit_document(self.config_file) as doc:
                merge_owned(doc, table_or_empty(state.get("owned")), desired)
                if selection is not None:
                    self.apply_selection(doc, selection)
            state["owned"] = desired
            for record, (path, extra_desired) in self.extra_owned_documents().items():
                with edit_document(path) as doc:
                    merge_owned(doc, table_or_empty(state.get(record)), extra_desired)
                state[record] = extra_desired
            if selection is not None:
                state["selection"] = selection["label"]

    def choose(self) -> Entry:
        """Ask for an entry, offering the saved selection first."""
        profiles = Profiles(self.name)
        while True:
            labels = [entry["label"] for entry in self.catalog.choices]
            current = read_document(self.state_file).get("selection")
            if isinstance(current, str) and current in labels:
                labels.remove(current)
                labels.insert(0, current)
            label = self.pick(labels, f"{self.name} · {profiles.name(self.root)}", manage=True)
            if label not in (SWITCH, FORK, DELETE):
                entry = copy.deepcopy(next(e for e in self.catalog.choices if e["label"] == label))
                return self.refine_choice(entry)
            try:
                if label == SWITCH:
                    configs = profiles.configurations()
                    selected = pick(list(configs), "Switch config for this launch")
                    self.set_root(configs[selected])
                elif label == FORK:
                    name = ask("Name for the new config (settings copied; fresh login and history)")
                    self.set_root(
                        profiles.fork(self.root, name, self.manifest.get("managedLinks", []))
                    )
                else:
                    if self.root == profiles.default or self.root.parent != profiles.directory:
                        raise SettingsError("the default and external configs cannot be deleted")
                    name = profiles.name(self.root)
                    confirmation = ask(
                        f"Close sessions using {name} first. Delete its settings and history? "
                        + f"Type {name} to confirm"
                    )
                    if confirmation == name:
                        profiles.delete(self.root)
                        self.set_root(profiles.default)
            except KeyboardInterrupt:
                continue
            except (SettingsError, OSError, ValueError) as error:
                pick(["Back"], str(error))

    def set_root(self, root: Path) -> None:
        self.root = root
        self.config_file = root / self.config_name
        self.state_file = root / "dotfiles-settings.json"

    def pick(self, labels: list[str], prompt: str, *, manage: bool = False) -> str:
        return pick(labels, prompt, manage=manage)

    def sync(self) -> None:
        """Activation always owns the default, independent of the caller's environment."""
        previous = self.root
        try:
            for root in Profiles(self.name).configurations().values():
                self.set_root(root)
                self.reconcile()
        finally:
            self.set_root(previous)

    def export_root(self, env: MutableMapping[str, str]) -> None:
        if self.root == Profiles(self.name).default:
            env.pop(self.home_env, None)
        else:
            env[self.home_env] = str(self.root)

    def select(self, launcher: str, args: list[str]) -> NoReturn:
        """Choose and save a selection, then start a fresh session with it."""
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            raise SettingsError(
                f"use {self.name}-select in a terminal; use {self.name} for scripts"
            )
        entry = self.choose()
        # Validate secrets before committing a selection that cannot launch.
        self.load_credentials(entry, {})
        self.reconcile(entry)
        self.export_root(os.environ)
        os.environ.pop(self.session_env, None)
        for key in self.managed_env:
            os.environ.pop(key, None)
        wrapper = self._cmux_wrapper()
        if wrapper is not None:
            os.environ[f"CMUX_CUSTOM_{self.name.upper()}_PATH"] = launcher
            os.execv(str(wrapper), [str(wrapper), *args])
        os.execv(launcher, [launcher, *args])

    def launch(self, args: list[str]) -> NoReturn:
        """Run the agent with the inherited or saved selection and its credentials."""
        env = os.environ.copy()
        self.export_root(env)
        session = self._inherited_session(env)
        inherited = session is not None
        if session is None:
            session = self.snapshot()
        # Only an explicit selection claims provider environment ownership.
        # Unconfigured installations retain caller-supplied credentials.
        if session.get("label"):
            for key in self.managed_env:
                env.pop(key, None)
            if inherited:
                env.update(session["env"])
            entry = self.catalog.find(session.get("label"))
            if entry is not None:
                self.load_credentials(entry, env)
        env[self.session_env] = json.dumps(session)
        executable = self.manifest["real"]
        os.execve(
            executable,
            [executable, *self.launch_args(session, args, inherited=inherited)],
            env,
        )

    def _inherited_session(self, env: dict[str, str]) -> Session | None:
        encoded = env.get(self.session_env)
        if not encoded:
            return None
        # Only a parent launch writes this variable.
        session = cast(Session, json.loads(encoded))
        return session if session.get("root") == str(self.root) else None

    def _cmux_wrapper(self) -> Path | None:
        """cmux's bundled wrapper for this agent, when selecting inside cmux."""
        if sys.platform != "darwin" or not os.environ.get("CMUX_SURFACE_ID"):
            return None
        integration = Path(os.environ.get("CMUX_SHELL_INTEGRATION_DIR", _CMUX_INTEGRATION))
        wrapper = integration.parent / "bin" / f"cmux-{self.name}-wrapper"
        if not os.access(wrapper, os.X_OK):
            raise SettingsError(f"settings saved, but cmux wrapper not found: {wrapper}")
        return wrapper
