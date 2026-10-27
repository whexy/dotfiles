"""`build`: plan_vN.json plus the Resolve script that creates its timeline."""

import hashlib
import shutil

from . import resolve_scripts, silence, timeline
from .common import UsageError, exec_line, resolve_path, write_json
from .context import Edit
from .media import frames_of
from .slots import all_definitions, passing_output

TIMEOUT = 60


def run_silences(root, refresh=False):
    edit = Edit(root)
    data = silence.load(root, edit.main, edit.spec, refresh=refresh)
    spans = data["silences"]
    return 0, {
        "ok": True,
        "file": root.rel(root.transcript_path(edit.main["path"]).with_suffix(".silences.json")),
        "count": data["count"],
        "noise_floor_db": data["noise_floor_db"],
        "threshold_db": data["threshold_db"],
        "threshold_from": data["threshold_from"],
        "min_duration": data["min_duration"],
        "silent_seconds": round(sum(e - s for s, e in spans), 1),
    }


def run_snap(root, dry_run=False):
    edit = Edit(root)
    edl = root.edl()
    new, report = timeline.snap(edl, edit.words, edit.silences, edit.fps, edit.cuts)
    check = timeline.validate(
        new, edit.words, edit.silences, edit.fps, edit.main["duration"], edit.cuts
    )
    if not dry_run and new != edl:
        shutil.copyfile(root.edl_path, root.edl_path.with_suffix(".json.bak"))
        write_json(root.edl_path, new)
    return 0, {
        "ok": True,
        "written": None if dry_run or new == edl else "edl.json (previous: edl.json.bak)",
        **report,
        "errors_after": check["errors"],
        "warnings_after": check["warnings"],
    }


def timeline_name(name, section, version):
    middle = f" {section}" if section else ""
    return f"{name}{middle} agent v{version}"


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def run_build(root, section=None, version=None, no_camera=False):
    edit = Edit(root)
    validation = edit.validate()
    if validation["errors"]:
        return 1, {
            "ok": False,
            "errors": validation["errors"],
            "warnings": validation["warnings"],
        }
    warnings = list(validation["warnings"])
    fps = edit.fps
    camera = None if no_camera else edit.camera
    if camera and camera.get("offset_frames") is None:
        raise UsageError(
            "camera offset unknown: run the sync script in Resolve, record it "
            "with `video-edit set-offset N`, or build with --no-camera"
        )

    versions = root.plan_versions()
    version = version or (versions[-1] + 1 if versions else 1)
    if version in versions:
        raise UsageError(f"plan v{version} exists; versions are never rebuilt")

    assembled, total = timeline.select_section(validation["ranges"], section)
    v1 = [
        {
            "source": "main",
            "src_in": r["src_in"],
            "src_out": r["src_out"],
            "rec_in": r["rec_in"],
            "rec_out": r["rec_out"],
            "range": r["position"],
        }
        for r in assembled
    ]
    v2 = []
    if camera:
        v2, more = timeline.camera_items(assembled, camera, fps)
        warnings += more

    inside = [
        o
        for o in validation["overlays"]
        if timeline.locate(assembled, frames_of(o["anchor"], fps))
    ]
    errors, placed = timeline.place_overlays(inside, assembled, fps, total)
    warnings += [f"{e}; not placed in this build" for e in errors]
    definitions = all_definitions(edit, validation)
    paths = {"main": resolve_path(edit.main["path"])}
    if camera:
        paths["camera"] = resolve_path(camera["path"])
    v3, markers, pending = [], [], {}
    for o in placed:
        slot_dir = root / "slots" / o["slot"]
        sig = definitions[o["slot"]]["signature"]
        done, why = passing_output(slot_dir, o["slot"], sig)
        if done:
            paths[o["slot"]] = root.resolve_path(done)
            v3.append(
                {
                    "source": "broll",
                    "slot": o["slot"],
                    "file": root.rel(done),
                    "src_in": 0,
                    "src_out": o["frames"],
                    "rec_in": o["rec_in"],
                    "rec_out": o["rec_out"],
                }
            )
        else:
            pending[o["slot"]] = why
        markers.append(
            {
                "frame": o["rec_in"],
                "color": "Green" if done else "Red",
                "name": o["slot"],
                "note": (o["reason"] or "")[:200],
                "duration": o["frames"],
                "custom": f"video-edit:{o['slot']}",
            }
        )

    name = edit.spec["name"]
    tracks = {"V1": v1, "A1": [dict(i) for i in v1], "V2": v2, "V3": v3}
    plan = {
        "version": version,
        "name": name,
        "timeline": timeline_name(name, section, version),
        "section": section,
        "fps": fps,
        "width": edit.spec["timeline"]["width"],
        "height": edit.spec["timeline"]["height"],
        "start_timecode": edit.spec["timeline"].get("start_timecode", "01:00:00:00"),
        "frame_convention": "0-based frames; *_out is exclusive; rec_* are "
        "offsets from the timeline start; AppendToTimeline endFrame = src_out",
        "duration_frames": total,
        "sources": {
            "main": {
                "path": edit.main["path"],
                "resolve_path": paths["main"],
                "file_name": edit.main["file_name"],
            },
            **(
                {
                    "camera": {
                        "path": camera["path"],
                        "resolve_path": paths["camera"],
                        "file_name": camera["file_name"],
                        "offset_frames": camera["offset_frames"],
                        "offset_changes": camera.get("offset_changes") or [],
                    }
                }
                if camera
                else {}
            ),
        },
        "edl_sha256": _sha(root.edl_path),
        "transcript": root.rel(edit.transcript_path),
        "ranges": [
            {
                k: r[k]
                for k in (
                    "position",
                    "edl_index",
                    "section",
                    "start",
                    "end",
                    "src_in",
                    "src_out",
                    "rec_in",
                    "rec_out",
                )
            }
            for r in assembled
        ],
        "tracks": tracks,
        "markers": markers,
    }
    plan_path = root / "resolve" / f"plan_v{version}.json"
    script_path = root / "resolve" / f"build_v{version}.py"
    run = exec_line(root.resolve_path(script_path))
    write_json(plan_path, plan)
    script_path.write_text(
        resolve_scripts.build_script(plan, paths, run), encoding="ascii"
    )
    return 0, {
        "ok": True,
        "version": version,
        "timeline": plan["timeline"],
        "duration_seconds": round(total / fps, 3),
        "plan": root.rel(plan_path),
        "script": root.rel(script_path),
        "run": run,
        "timeout": TIMEOUT,
        "tracks": {k: len(v) for k, v in tracks.items()},
        "broll": {"placed": [i["slot"] for i in v3], "pending": pending},
        "warnings": warnings,
    }


def run_readback_script(root, version=None):
    plan = root.plan(version)
    otio = root / "verify" / f"readback_v{plan['version']}.otio"
    otio.parent.mkdir(parents=True, exist_ok=True)
    script_path = root / "resolve" / f"readback_v{plan['version']}.py"
    run = exec_line(root.resolve_path(script_path))
    script_path.write_text(
        resolve_scripts.readback_script(plan, root.resolve_path(otio), run),
        encoding="ascii",
    )
    return 0, {
        "ok": True,
        "version": plan["version"],
        "timeline": plan["timeline"],
        "script": root.rel(script_path),
        "otio": root.rel(otio),
        "run": run,
        "timeout": TIMEOUT,
        "next": f"video-edit verify-timeline --version {plan['version']}",
    }
