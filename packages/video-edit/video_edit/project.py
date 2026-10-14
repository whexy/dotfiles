"""`init`, `sync-script` and `set-offset`: setting up an edit root."""

from pathlib import Path
import shlex
import shutil

from . import resolve_scripts, silence, timeline
from .common import (
    Root,
    UsageError,
    exec_line,
    read_json,
    safe_name,
    to_windows,
    write_json,
)
from .media import probe_source

STYLE_TEMPLATE = Path(__file__).resolve().parent.parent / "style"
DIRS = ("transcripts", "slots", "resolve", "verify", "subtitles", "style")
# whisper-1 mishearings of names the user says often; subtitles only.
GLOSSARY = {
    "telscope": "Tailscale",
    "proxmos": "Proxmox",
    "cloud fair": "Cloudflare",
    "ink os": "Incus",
    "too long to draw": "tldraw",
}


def default_spec(name, main):
    return {
        "version": 1,
        "name": name,
        "timeline": {
            "width": main["width"],
            "height": main["height"],
            "fps": main["fps"],
            "start_timecode": "01:00:00:00",
        },
        "final": {
            "codec": "hevc",
            "encoder": "hevc_nvenc",
            "profile": "main",
            "pix_fmt": "yuv420p",
            "color": {
                "primaries": "bt709",
                "transfer": "bt709",
                "matrix": "bt709",
                "range": "tv",
            },
            "nvenc": {
                "preset": "p5",
                "tune": "hq",
                "cq": 16,
                "maxrate": "200M",
                "bufsize": "400M",
            },
        },
        "draft": {"width": 1920, "height": 1080, "fps": 30},
        "rules": {"text": False, "textWhitelist": []},
        "cuts": dict(timeline.CUT_DEFAULTS),
        "silence": dict(silence.DEFAULTS),
        "subtitles": {
            "maxChars": 17,
            "minDuration": 0.7,
            "maxDuration": 7.0,
            "linger": 0.3,
            "bridgeGap": 0.5,
        },
        "glossary": dict(GLOSSARY),
    }


def _source(path):
    info = probe_source(path)
    info["windows_path"] = to_windows(path)
    return info


def run_init(main, camera, name):
    main = Path(main).absolute()
    if not main.is_file():
        raise UsageError(f"not a file: {main}")
    root = Root(main.parent / "edit" / safe_name(name))
    warnings = []
    sources = {"version": 1, "main": _source(main)}
    if not sources["main"]["has_audio"]:
        warnings.append("main source has no audio: transcribe and sync need it")
    if sources["main"]["vfr"]:
        warnings.append("main source looks variable-frame-rate; frame math assumes CFR")
    if sources["main"]["start_timecode"] != "00:00:00:00":
        warnings.append(
            f"main source starts at timecode {sources['main']['start_timecode']}; "
            "source frames are counted from the first frame regardless"
        )
    old = read_json(root.sources_path) if root.sources_path.exists() else None
    if old and old["main"]["path"] != sources["main"]["path"]:
        raise UsageError(
            f"{root.path} already belongs to {old['main']['path']}; pick another --name"
        )
    if camera:
        cam = _source(Path(camera).absolute())
        previous = (old or {}).get("camera") or {}
        same = previous.get("path") == cam["path"]
        cam["offset_frames"] = previous.get("offset_frames") if same else None
        cam["offset_changes"] = previous.get("offset_changes", []) if same else []
        sources["camera"] = cam
    elif old and old.get("camera"):
        sources["camera"] = old["camera"]

    created = []
    for d in DIRS:
        (root / d).mkdir(parents=True, exist_ok=True)
    write_json(root.sources_path, sources)
    if not root.spec_path.exists():
        write_json(root.spec_path, default_spec(name.strip(), sources["main"]))
        created.append("spec.json")
    for template in sorted(STYLE_TEMPLATE.iterdir()):
        target = root / "style" / template.name
        if not target.exists():
            shutil.copyfile(template, target)
            target.chmod(0o644)
            created.append(f"style/{template.name}")

    transcript = root.transcript_path(main)
    return 0, {
        "ok": True,
        "root": str(root.path),
        "created": created,
        "sources": {
            role: {k: s[k] for k in ("file_name", "fps", "frames", "duration", "width", "height")}
            for role, s in sources.items()
            if role != "version"
        },
        "warnings": warnings,
        "next": (
            f"cd {shlex.quote(str(root.path))} && transcribe "
            f"{shlex.quote(str(main))} --format json -o "
            f"{shlex.quote(root.rel(transcript))}"
            if not transcript.exists()
            else "transcript cached; read it with transcribe --from-json"
        ),
    }


def run_sync_script(root):
    sources = root.sources()
    camera = sources.get("camera")
    if not camera:
        raise UsageError("no camera in sources.json: run init with --camera")
    name = root.spec()["name"]
    path = root / "resolve" / "sync.py"
    run = exec_line(root.windows(path))
    path.write_text(
        resolve_scripts.sync_script(
            name, sources["main"]["windows_path"], camera["windows_path"], run
        ),
        encoding="ascii",
    )
    return 0, {
        "ok": True,
        "script": root.rel(path),
        "run": run,
        "timeout": 60,
        "next": "video-edit set-offset <camera_offset_frames from the result>",
    }


def run_set_offset(root, frames, at=None):
    sources = root.sources()
    camera = sources.get("camera")
    if not camera:
        raise UsageError("no camera in sources.json: run init with --camera")
    if at is None:
        camera["offset_frames"] = frames
    else:
        if camera.get("offset_frames") is None:
            raise UsageError("set the base offset first: video-edit set-offset N")
        changes = [
            c for c in camera.get("offset_changes") or [] if abs(c["at"] - at) > 1e-6
        ]
        changes.append({"at": at, "offset_frames": frames})
        camera["offset_changes"] = sorted(changes, key=lambda c: c["at"])
    write_json(root.sources_path, sources)
    return 0, {
        "ok": True,
        "convention": "camera frame = main frame - offset_frames",
        "offset_frames": camera["offset_frames"],
        "offset_changes": camera.get("offset_changes") or [],
    }
