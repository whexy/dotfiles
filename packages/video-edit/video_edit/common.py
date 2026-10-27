"""Edit-root files, JSON I/O, errors and the paths Resolve opens."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

EXIT_OK, EXIT_FAIL, EXIT_USAGE, EXIT_MEDIA, EXIT_TRANSCRIBE, EXIT_NOKEY = range(6)

MACOS = sys.platform == "darwin"


class ToolError(Exception):
    exit_code = EXIT_FAIL


class UsageError(ToolError):
    exit_code = EXIT_USAGE


class MediaError(ToolError):
    exit_code = EXIT_MEDIA


class TranscribeError(ToolError):
    exit_code = EXIT_TRANSCRIBE


class NoKeyError(ToolError):
    exit_code = EXIT_NOKEY


def eprint(*args):
    print("video-edit:", *args, file=sys.stderr)


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError as err:
        raise UsageError(f"missing {path}") from err
    except ValueError as err:
        raise UsageError(f"{path} is not valid JSON: {err}") from err


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    tmp.replace(path)


def safe_name(name):
    """A folder/file name Windows accepts; CJK and spaces are kept."""
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', " ", name)
    cleaned = re.sub(r"\s+", " ", cleaned).strip().rstrip(".")
    if not cleaned:
        raise UsageError(f"name {name!r} has no usable characters")
    return cleaned


def resolve_path(path):
    """The path Resolve opens a file by.

    Resolve runs beside this tool on macOS. Under WSL it is the Windows app,
    so the path is Windows': `wslpath -w`, else the /mnt/<drive> rule.
    """
    path = os.path.abspath(str(path))
    if MACOS:
        return path
    # Agents under systemd user services lack /bin on PATH, so try the
    # interop binary by absolute path first.
    for exe in ("/bin/wslpath", shutil.which("wslpath")):
        if exe and os.path.exists(exe):
            result = subprocess.run(
                [exe, "-w", path], capture_output=True, text=True
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
    return mnt_to_windows(path)


def mnt_to_windows(path):
    match = re.match(r"^/mnt/([a-zA-Z])(/.*)?$", path)
    if not match:
        raise UsageError(
            f"cannot map {path} to a Windows path: keep footage on a Windows "
            "drive (/mnt/<drive>/...)"
        )
    rest = (match.group(2) or "/").replace("/", "\\")
    return match.group(1).upper() + ":" + rest


def exec_line(path):
    """The one-line run_script_unsafe body that runs a generated script."""
    return f"exec(open({ascii(path)}, encoding='utf-8').read())"


class Root:
    """An edit root: `<footage dir>/edit/<name>/`."""

    def __init__(self, path):
        self.path = Path(path).absolute()
        self._resolve_path = None

    def __truediv__(self, rel):
        return self.path / rel

    @property
    def spec_path(self):
        return self.path / "spec.json"

    @property
    def sources_path(self):
        return self.path / "sources.json"

    @property
    def edl_path(self):
        return self.path / "edl.json"

    def spec(self):
        return read_json(self.spec_path)

    def sources(self):
        return read_json(self.sources_path)

    def edl(self):
        return read_json(self.edl_path)

    def transcript_path(self, source_path):
        return self.path / "transcripts" / f"{Path(source_path).stem}.json"

    def rel(self, path):
        try:
            return str(Path(path).absolute().relative_to(self.path))
        except ValueError:
            return str(path)

    def resolve_path(self, path):
        """Resolve's path of a file inside the root, from one wslpath call."""
        if self._resolve_path is None:
            self._resolve_path = resolve_path(self.path)
        rel = Path(path).absolute().relative_to(self.path)
        sep = "/" if MACOS else "\\"
        return self._resolve_path.rstrip(sep) + sep + sep.join(rel.parts)

    def plan_versions(self):
        found = []
        for p in (self.path / "resolve").glob("plan_v*.json"):
            m = re.fullmatch(r"plan_v(\d+)\.json", p.name)
            if m:
                found.append(int(m.group(1)))
        return sorted(found)

    def plan(self, version=None):
        versions = self.plan_versions()
        if version is None:
            if not versions:
                raise UsageError("no build yet: run `video-edit build` first")
            version = versions[-1]
        path = self.path / "resolve" / f"plan_v{version}.json"
        if not path.exists():
            raise UsageError(f"no plan v{version} (have: {versions or 'none'})")
        return read_json(path)


def find_root(explicit=None):
    if explicit:
        root = Path(explicit)
        if not (root / "spec.json").exists():
            raise UsageError(f"{root} is not an edit root (no spec.json)")
        return Root(root)
    here = Path.cwd().absolute()
    for candidate in (here, *here.parents):
        if (candidate / "spec.json").exists() and (
            candidate / "sources.json"
        ).exists():
            return Root(candidate)
    raise UsageError(
        "not inside an edit root (no spec.json + sources.json here or above); "
        "run `video-edit init` or pass --root"
    )
