"""B-roll slot definitions (`slots/<id>/slot.json`) and their finished outputs.

A slot carries every time a B-roll worker needs already converted to the
slot's own clock (seconds and frames from the clip's first frame), so the
worker never maps transcript or timeline times itself.
"""

import hashlib
import json
import math
from pathlib import Path
import re

from .common import UsageError, read_json, write_json
from .context import Edit
from .media import frames_of
from .timeline import kept_words
from .transcript import join

PHRASE_GAP = 0.3
SUBDIRS = ("src", "render", "draft", "out")


def draft_frames(duration, fps):
    """Frames HyperFrames renders for `duration`: it rounds up unless the
    product is within 0.001 frame of a whole number."""
    return math.ceil(duration * fps - 0.001)


def _times(t, end, fps, draft_fps):
    return {
        "t": round(t, 3),
        "end": round(end, 3),
        "frame": frames_of(t, fps),
        "end_frame": frames_of(end, fps),
        "draft_frame": frames_of(t, draft_fps),
        "draft_end_frame": frames_of(end, draft_fps),
    }


def signature(slot):
    """Changes whenever the clip length or the speech under it moves."""
    key = {
        "fps": slot["fps"],
        "width": slot["width"],
        "height": slot["height"],
        "frames": slot["frames"],
        "beats": [[b["src_index"], b["frame"]] for b in slot["beats"]],
    }
    blob = json.dumps(key, sort_keys=True).encode()
    return hashlib.sha256(blob).hexdigest()[:16]


def definition(edit, overlay, kept, slot_dir):
    spec = edit.spec
    fps = edit.fps
    final = spec["timeline"]
    draft = spec["draft"]
    start = overlay["rec_in"] / fps
    frames = overlay["frames"]
    end = start + frames / fps
    beats = []
    for w in kept:
        if w["out_end"] > start and w["out_start"] < end:
            beats.append(
                {
                    "i": w["i"],
                    "src_index": w["src_index"],
                    "word": w["word"],
                    **_times(w["out_start"] - start, w["out_end"] - start, fps, draft["fps"]),
                }
            )
    phrases, current = [], []
    for b in beats:
        if current and b["t"] - current[-1]["end"] >= PHRASE_GAP:
            phrases.append(current)
            current = []
        current.append(b)
    if current:
        phrases.append(current)
    anchor_t = (overlay["anchor_rec"] - overlay["rec_in"]) / fps
    anchor_word = min(
        beats,
        key=lambda b: (0 if b["t"] <= anchor_t <= b["end"] else 1, abs(b["t"] - anchor_t)),
        default=None,
    )
    slot_dir = Path(slot_dir)
    slot = {
        "version": 1,
        "id": overlay["slot"],
        "reason": overlay["reason"],
        "fps": fps,
        "width": final["width"],
        "height": final["height"],
        "frames": frames,
        "duration": frames / fps,
        "alpha": False,
        "draft": {
            "fps": draft["fps"],
            "width": draft["width"],
            "height": draft["height"],
            "frames": draft_frames(frames / fps, draft["fps"]),
        },
        "timeline_offset_frames": overlay["rec_in"],
        "timeline_offset_seconds": round(start, 6),
        "section": overlay["section"],
        "anchor": {
            "t": round(anchor_t, 3),
            "frame": overlay["anchor_rec"] - overlay["rec_in"],
            "draft_frame": frames_of(anchor_t, draft["fps"]),
            "word": anchor_word["word"] if anchor_word else None,
        },
        "beats": beats,
        "phrases": [
            {
                "text": join(b["word"] for b in p),
                **_times(p[0]["t"], p[-1]["end"], fps, draft["fps"]),
                "words": [b["i"] for b in p],
            }
            for p in phrases
        ],
        "voiceover": join(b["word"] for b in beats),
        "rules": spec.get("rules", {}),
        "spec": str(edit.root.spec_path),
        "style": str(edit.root / "style"),
        "paths": {
            "dir": str(slot_dir),
            "brief": str(slot_dir / "brief.md"),
            "report": str(slot_dir / "report.md"),
            **{name: str(slot_dir / name) for name in SUBDIRS},
        },
    }
    slot["signature"] = signature(slot)
    return slot


def all_definitions(edit, validation):
    kept = kept_words(validation["ranges"], edit.words, edit.fps)
    return {
        o["slot"]: definition(edit, o, kept, edit.root / "slots" / o["slot"])
        for o in validation["overlays"]
    }


def outputs(slot_dir, slot_id):
    """[(N, path)] of out/<id>_vN.mp4, oldest first."""
    found = []
    for p in (Path(slot_dir) / "out").glob(f"{slot_id}_v*.mp4"):
        m = re.fullmatch(rf"{re.escape(slot_id)}_v(\d+)\.mp4", p.name)
        if m:
            found.append((int(m.group(1)), p))
    return sorted(found)


def check_record(path):
    return Path(path).with_suffix(".check.json")


def passing_output(slot_dir, slot_id, sig):
    """(newest output that passed `check` for this slot definition, why not)."""
    reasons = []
    for n, path in reversed(outputs(slot_dir, slot_id)):
        record = check_record(path)
        if not record.exists():
            reasons.append(f"{path.name} not checked")
            continue
        data = read_json(record)
        stat = path.stat()
        if data.get("mode") != "final" or not data.get("pass"):
            reasons.append(f"{path.name} failed check")
        elif data.get("signature") != sig:
            reasons.append(
                f"{path.name} was made for an older slot definition "
                "(the cut under it changed: re-run `video-edit slots` and re-render)"
            )
        elif data.get("size") != stat.st_size or data.get("mtime_ns") != stat.st_mtime_ns:
            reasons.append(f"{path.name} changed after its check")
        else:
            return path, None
    return None, "; ".join(reasons) or "no finalized output yet"


def run_slots(root):
    edit = Edit(root)
    validation = edit.validate()
    if validation["errors"]:
        return 1, {
            "ok": False,
            "errors": validation["errors"],
            "warnings": validation["warnings"],
        }
    defs = all_definitions(edit, validation)
    report = []
    for slot_id, slot in defs.items():
        slot_dir = Path(slot["paths"]["dir"])
        for name in SUBDIRS:
            (slot_dir / name).mkdir(parents=True, exist_ok=True)
        previous = slot_dir / "slot.json"
        changed = previous.exists() and read_json(previous).get("signature") != slot["signature"]
        write_json(previous, slot)
        done, why = passing_output(slot_dir, slot_id, slot["signature"])
        report.append(
            {
                "id": slot_id,
                "slot": root.rel(previous),
                "frames": slot["frames"],
                "seconds": slot["duration"],
                "timeline_offset_frames": slot["timeline_offset_frames"],
                "words": len(slot["beats"]),
                "voiceover": slot["voiceover"],
                "brief": (slot_dir / "brief.md").exists(),
                "changed": changed,
                "passing": root.rel(done) if done else None,
                "pending": why,
            }
        )
    known = set(defs)
    orphans = sorted(
        p.name for p in (root / "slots").glob("*") if p.is_dir() and p.name not in known
    )
    return 0, {
        "ok": True,
        "slots": report,
        "orphans": orphans,
        "warnings": validation["warnings"],
    }


def load_slot(slot_dir):
    slot_dir = Path(slot_dir)
    path = slot_dir / "slot.json" if slot_dir.is_dir() else slot_dir
    if not path.exists():
        raise UsageError(f"no slot.json at {path}: run `video-edit slots` first")
    return read_json(path), path.parent
