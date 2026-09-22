"""Writable agent preferences, narrow Nix reconciliation, and runtime credentials."""

import contextlib
import copy
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import tomlkit


class SettingsError(Exception):
    pass


def read_document(path):
    if not path.exists() and not path.is_symlink():
        return tomlkit.document() if path.suffix == ".toml" else {}
    text = path.read_text()
    doc = tomlkit.parse(text) if path.suffix == ".toml" else json.loads(text)
    if not isinstance(doc, dict):
        raise SettingsError(f"expected an object in {path}")
    return doc


def fingerprint(path):
    if not path.exists() and not path.is_symlink():
        return None
    stat = path.lstat()
    return (stat.st_ino, stat.st_mtime_ns, path.read_bytes())


def save_document(path, doc, before):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink() and not str(path.resolve()).startswith("/nix/store/"):
        raise SettingsError(f"refusing to replace non-Nix symlink: {path}")
    text = tomlkit.dumps(doc) if path.suffix == ".toml" else json.dumps(doc, indent=2) + "\n"
    if before is not None and before[2] == text.encode() and not path.is_symlink():
        return
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as target:
            target.write(text)
            target.flush()
            os.fsync(target.fileno())
        if fingerprint(path) != before:
            raise SettingsError(f"{path} changed while editing; retry")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def edit_document(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.parent / f".{path.name}.dotfiles.lock", "a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        before = fingerprint(path)
        doc = read_document(path)
        yield doc
        save_document(path, doc, before)


def merge_owned(doc, previous, desired):
    """Remove only unchanged retired values; preserve unrelated keys/list entries."""
    for key, old in previous.items():
        if key not in desired and key in doc:
            if isinstance(old, dict) and isinstance(doc[key], dict):
                merge_owned(doc[key], old, {})
                if not doc[key]:
                    del doc[key]
            elif isinstance(old, list) and isinstance(doc[key], list):
                doc[key] = [item for item in doc[key] if item not in old]
            elif doc[key] == old:
                del doc[key]
    for key, value in desired.items():
        if isinstance(value, dict):
            if key not in doc:
                doc[key] = {}
            if not isinstance(doc[key], dict):
                raise SettingsError(f"expected a table/object at {key}")
            merge_owned(doc[key], previous.get(key, {}), value)
        elif isinstance(value, list):
            existing = doc.get(key, [])
            if not isinstance(existing, list):
                raise SettingsError(f"expected a list at {key}")
            old = previous.get(key, [])
            doc[key] = [item for item in existing if item not in old and item not in value] + value
        else:
            doc[key] = value


def secret_path(fragment):
    # Agenix may qualify getconf with its Nix store path. Recognize only this
    # substitution and run the system utility, never a command from the catalog.
    darwin = re.fullmatch(
        r"\$\((?:getconf|/usr/bin/getconf|/nix/store/[a-z0-9]{32}-[A-Za-z0-9+._?=-]+/bin/getconf) DARWIN_USER_TEMP_DIR\)(/[^$]*)",
        fragment,
    )
    if darwin:
        temporary = subprocess.check_output(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()
        fragment = temporary.rstrip("/") + darwin.group(1)
    fragment = os.path.expandvars(fragment)
    if "$" in fragment or not fragment.startswith("/"):
        raise SettingsError("unresolved credential path")
    return Path(fragment)


class AgentSettings:
    def __init__(self, manifest):
        self.manifest = manifest
        self.name = manifest["name"]
        home_var = "CLAUDE_CONFIG_DIR" if self.name == "claude" else "CODEX_HOME"
        self.root = Path(os.environ.get(home_var, str(Path.home() / f".{self.name}"))).expanduser().absolute()
        self.config = self.root / ("settings.json" if self.name == "claude" else "config.toml")
        self.state = self.root / "dotfiles-settings.json"
        self.marker = f"DOTFILES_{self.name.upper()}_SESSION"
        self.entries = manifest["entries"]
        candidates = [candidate for entry in self.entries for candidate in entry.get("fusion", {}).get("candidates", [])]
        self.all_entries = self.entries + candidates
        self.managed_env = set(manifest.get("resetEnv", []))
        for entry in self.all_entries:
            self.managed_env.update(entry.get("env", {}))
            self.managed_env.update(entry.get("secrets", {}))
            self.managed_env.update(role["export"] for role in entry.get("fusion", {}).get("roles", []))
        if self.name == "claude":
            self.managed_env.update(["ANTHROPIC_CUSTOM_HEADERS", "CLAUDE_CODE_SUBAGENT_MODEL", "CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT"])

    def pick(self, labels, prompt):
        result = subprocess.run(
            [self.manifest["fzf"], "--reverse", "--height=~100%", f"--prompt={prompt}> "],
            input="\n".join(labels) + "\n", text=True, stdout=subprocess.PIPE,
        )
        if result.returncode in (1, 130):
            raise KeyboardInterrupt
        if result.returncode or result.stdout.strip() not in labels:
            raise SettingsError("model selector failed")
        return result.stdout.strip()

    def choose(self):
        labels = [entry["label"] for entry in self.entries]
        current = read_document(self.state).get("selection")
        if current in labels:
            labels.remove(current)
            labels.insert(0, current)
        label = self.pick(labels, self.name)
        entry = copy.deepcopy(next(entry for entry in self.entries if entry["label"] == label))
        if "fusion" in entry:
            fusion = entry["fusion"]
            main = self.pick([c["label"] for c in fusion["candidates"]], "main model")
            entry = copy.deepcopy(next(c for c in fusion["candidates"] if c["label"] == main))
            provider = main.split("/", 1)[0]
            labels = [c["label"] for c in fusion["candidates"] if c["label"].startswith(provider + "/")]
            entry.setdefault("env", {}).update({"CLAUDE_CODE_SUBAGENT_MODEL": main.split("/", 1)[1], "CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT": "1"})
            for role in fusion["roles"]:
                entry["env"][role["export"]] = self.pick(labels, role["prompt"]).split("/", 1)[1]
        return entry

    def reconcile(self, selection=None):
        # All our multi-file writers serialize on the state lock. Each native
        # file also gets an optimistic check against non-cooperating writers.
        with edit_document(self.state) as state:
            old = state.get("owned", {})
            desired = copy.deepcopy(self.manifest.get("maintainedSettings", {}))
            if self.name == "codex":
                for entry in self.entries:
                    desired.setdefault("model_providers", {}).update(entry.get("settings", {}).get("model_providers", {}))
                desired["mcp_servers"] = self.manifest.get("mcpServers", {})
            with edit_document(self.config) as doc:
                merge_owned(doc, old, desired)
                if selection is not None:
                    if self.name == "claude":
                        env = doc.setdefault("env", {})
                        for key in self.managed_env:
                            env.pop(key, None)
                        values = copy.deepcopy(selection.get("env", {}))
                        model = values.pop("ANTHROPIC_MODEL", None)
                        doc.pop("model", None)
                        if model:
                            doc["model"] = model
                        env.update(values)
                    else:
                        for key in ("model", "model_provider", "profile", "preferred_auth_method"):
                            doc.pop(key, None)
                        doc.update({key: value for key, value in selection.get("settings", {}).items() if key != "model_providers"})
            if self.name == "claude":
                # Claude's user MCP registry is separate from settings.json.
                mcp_path = self.root / ".claude.json" if os.environ.get("CLAUDE_CONFIG_DIR") else Path.home() / ".claude.json"
                desired_mcp = {"mcpServers": self.manifest.get("mcpServers", {})}
                with edit_document(mcp_path) as doc:
                    merge_owned(doc, state.get("ownedMcp", {}), desired_mcp)
                state["ownedMcp"] = desired_mcp
            state["owned"] = desired
            if selection is not None:
                state["selection"] = selection["label"]

    def credentials(self, entry, env):
        for key, fragment in entry.get("secrets", {}).items():
            value = secret_path(fragment).read_text().rstrip("\n")
            if not value or "\n" in value or "\r" in value:
                raise SettingsError(f"missing or invalid credential for {key}")
            env[key] = value
        if entry.get("secretHeaders"):
            env["ANTHROPIC_CUSTOM_HEADERS"] = "\n".join(f"{header}: {env[key]}" for header, key in entry["secretHeaders"].items())

    def snapshot(self):
        doc = read_document(self.config)
        state = read_document(self.state)
        entry = next((e for e in self.all_entries if e["label"] == state.get("selection")), {})
        if self.name == "codex":
            provider = doc.get("model_provider", "openai")
            entry = next((e for e in self.entries if e.get("settings", {}).get("model_provider") == provider), {})
            settings = {"model_provider": provider}
            if "model" in doc:
                settings["model"] = doc["model"]
            if entry:
                settings["model_providers"] = entry["settings"]["model_providers"]
            values = {}
            if not entry and provider == "openai" and state.get("selection"):
                entry = next((e for e in self.entries if "settings" not in e), {})
        else:
            credential_keys = {key for e in self.all_entries for key in e.get("secrets", {})}
            credential_keys.update(["ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_CUSTOM_HEADERS"])
            values = {key: value for key, value in doc.get("env", {}).items() if key in self.managed_env and key not in credential_keys}
            if "model" in doc:
                values["ANTHROPIC_MODEL"] = doc["model"]
            if values.get("ANTHROPIC_BASE_URL") != entry.get("env", {}).get("ANTHROPIC_BASE_URL"):
                entry = {}
            settings = {}
        return {"root": str(self.root), "label": entry.get("label"), "env": values, "settings": settings}

    def claude_inherited_args(self, snapshot, args):
        # Claude file env wins over shell exports. One --settings document is
        # required: duplicate flags can discard cmux's injected hooks entirely.
        values = {key: "" for key in self.managed_env if key not in {k for e in self.all_entries for k in e.get("secrets", {})}}
        for key in ("ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_CUSTOM_HEADERS"):
            values.pop(key, None)
        values.update(snapshot["env"])
        settings = {"env": values, "model": snapshot["env"].get("ANTHROPIC_MODEL", "")}

        def overlay(target, source):
            for key, value in source.items():
                if isinstance(value, dict) and isinstance(target.get(key), dict):
                    overlay(target[key], value)
                elif isinstance(value, list) and isinstance(target.get(key), list):
                    target[key].extend(value)
                else:
                    target[key] = value

        forwarded = []
        index = 0
        while index < len(args):
            arg = args[index]
            if arg == "--":
                forwarded.extend(args[index:])
                break
            if arg == "--settings" and index + 1 < len(args):
                index += 1
                value = args[index]
            elif arg.startswith("--settings="):
                value = arg.partition("=")[2]
            else:
                forwarded.append(arg)
                index += 1
                continue
            if not value.lstrip().startswith("{") and not Path(value).is_file():
                raise SettingsError("inherited launch: settings file does not exist")
            source = json.loads(value) if value.lstrip().startswith("{") else read_document(Path(value))
            if not isinstance(source, dict):
                raise SettingsError("inherited launch: expected a settings object")
            overlay(settings, source)
            index += 1
        return ["--settings", json.dumps(settings), *forwarded]

    def launch(self, args):
        env = os.environ.copy()
        inherited = env.get(self.marker)
        snapshot = json.loads(inherited) if inherited else self.snapshot()
        if snapshot.get("root") != str(self.root):
            inherited = None
            snapshot = self.snapshot()
        entry = next((e for e in self.all_entries if e["label"] == snapshot.get("label")), {})
        # Only an explicit selection claims provider environment ownership.
        # Unconfigured installations retain caller-supplied credentials.
        selected = bool(snapshot.get("label"))
        if selected:
            for key in self.managed_env:
                env.pop(key, None)
            if inherited:
                env.update(snapshot["env"])
            self.credentials(entry, env)
        env[self.marker] = json.dumps(snapshot)
        inherited_args = []
        if selected and self.name == "claude":
            # Claude hot-reloads user env. Pin this session's nonsecret routing
            # so another selector cannot redirect its already-loaded API key.
            args = self.claude_inherited_args(snapshot, args)
        if inherited and self.name == "codex":
            # Dedicated --model wins over config defaults; cmux and caller -c
            # arguments follow these defaults and are never persisted.
            for key, value in snapshot["settings"].items():
                table = tomlkit.inline_table() if isinstance(value, dict) else None
                if table is not None:
                    table.update(value)
                    encoded = table.as_string()
                else:
                    encoded = tomlkit.item(value).as_string()
                inherited_args.extend(["-c", f"{key}={encoded}"])
        os.execve(self.manifest["real"], [self.manifest["real"], *inherited_args, *args], env)

    def select(self, launcher, args):
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            raise SettingsError(f"use {self.name}-select in a terminal; use {self.name} for scripts")
        entry = self.choose()
        # Validate secrets before committing a selection that cannot launch.
        self.credentials(entry, {})
        self.reconcile(entry)
        os.environ.pop(self.marker, None)
        for key in self.managed_env:
            os.environ.pop(key, None)
        if sys.platform == "darwin" and os.environ.get("CMUX_SURFACE_ID"):
            integration = Path(os.environ.get("CMUX_SHELL_INTEGRATION_DIR", "/Applications/cmux.app/Contents/Resources/shell-integration"))
            wrapper = integration.parent / "bin" / f"cmux-{self.name}-wrapper"
            if not os.access(wrapper, os.X_OK):
                raise SettingsError(f"settings saved, but cmux wrapper not found: {wrapper}")
            os.environ[f"CMUX_CUSTOM_{self.name.upper()}_PATH"] = launcher
            os.execv(str(wrapper), [str(wrapper), *args])
        os.execv(launcher, [launcher, *args])


def main():
    manifest_path, action, *args = sys.argv[1:]
    manager = AgentSettings(json.loads(Path(manifest_path).read_text()))
    if action == "sync":
        manager.reconcile()
    elif action == "select":
        manager.select(args[0], args[1:])
    elif action == "launch":
        manager.launch(args)
    else:
        raise SettingsError(f"unknown action: {action}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
    except (SettingsError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"agent-settings: {error}", file=sys.stderr)
        sys.exit(1)
