"""EDL validation, edge snapping and frame math.

Frame convention, used by every plan_vN.json field and generated script:
frames are 0-based; `*_in` is the first frame of an item and `*_out` the
first frame after it, so a 755-frame clip from source frame 1112 is
src_in 1112, src_out 1867. `rec_*` are offsets from the timeline start.
Resolve's AppendToTimeline takes endFrame = src_out: on Resolve 21.1,
endFrame = src_out - 1 produced 754-frame clips and 1-frame gaps, while
endFrame = src_out assembled 265 clips gap-free.

Cut edges are judged against detected silences (silence.py), not whisper
word edges. An in-point belongs `pre` seconds before speech onset (the
end of its silence) and an out-point `post` seconds after speech offset
(the start of its silence); the defaults come from the user's approved
cuts (median 94 ms before onset, 283 ms after offset).
"""

import bisect
import math
import re
import statistics

from .common import UsageError
from .media import frames_of

SLOT_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
EPS = 1e-6
CUT_DEFAULTS = {
    "pre": 0.09,
    "preMin": 0.05,
    "preMax": 0.15,
    "post": 0.25,
    "postMin": 0.1,
    "postMax": 0.3,
    "reach": 0.3,
}


def cut_settings(spec):
    return {**CUT_DEFAULTS, **(spec.get("cuts") or {})}


def check_fps(spec, sources):
    """Errors when the timeline and main frame rates can't share frame math."""
    errors = []
    fps = spec["timeline"]["fps"]
    if float(fps) != int(fps):
        errors.append(
            f"timeline fps {fps} is fractional; v1 supports whole frame rates only"
        )
    main_fps = sources["main"]["fps"]
    if abs(float(main_fps) - float(fps)) > 1e-6:
        errors.append(
            f"main source is {main_fps} fps but the timeline is {fps} fps; "
            "v1 needs them equal (set spec.json timeline.fps or re-record)"
        )
    return errors


def _num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _mid(w):
    return (w["start"] + w["end"]) / 2


class Words:
    """Transcript words indexed for membership queries."""

    def __init__(self, words):
        self.words = words
        self.starts = [w["start"] for w in words]
        self.mid_order = sorted(range(len(words)), key=lambda i: _mid(words[i]))
        self.mids = [_mid(words[i]) for i in self.mid_order]

    def containing(self, t):
        """A word strictly straddling time t, if any."""
        i = bisect.bisect_right(self.starts, t)
        for w in self.words[max(0, i - 8) : i]:
            if w["start"] < t - EPS and w["end"] > t + EPS:
                return w
        return None

    def within(self, t0, t1):
        """Words whose midpoint lies in [t0, t1), in source order."""
        lo = bisect.bisect_left(self.mids, t0)
        hi = bisect.bisect_left(self.mids, t1)
        return sorted(
            (self.words[i] for i in self.mid_order[lo:hi]), key=lambda w: w["index"]
        )


def _frame_window(lo, hi, fps):
    """Whole frames f with lo <= f/fps <= hi, or None."""
    f_lo = math.ceil(lo * fps - EPS)
    f_hi = math.floor(hi * fps + EPS)
    return (f_lo, f_hi) if f_lo <= f_hi else None


def _label(w):
    return f"#{w['index']} '{w['word']}' [{w['start']:.3f}-{w['end']:.3f}]"


def edge_window(kind, span, fps, cuts):
    """(frames allowed inside silence `span`, preferred time) for an edge."""
    s, e = span
    if kind == "in":
        lo, hi, want = max(s, e - cuts["preMax"]), e - cuts["preMin"], e - cuts["pre"]
    else:
        lo, hi, want = s + cuts["postMin"], min(e, s + cuts["postMax"]), s + cuts["post"]
    return _frame_window(lo, hi, fps), want


def parse_ranges(edl, fps, duration):
    errors, ranges = [], []
    raw = edl.get("ranges")
    if not isinstance(raw, list) or not raw:
        return ["edl.json needs a non-empty `ranges` list"], []
    total = frames_of(duration, fps)
    for k, r in enumerate(raw):
        if not isinstance(r, dict) or not (_num(r.get("start")) and _num(r.get("end"))):
            errors.append(f"range {k}: needs numeric start and end")
            continue
        src_in, src_out = frames_of(r["start"], fps), frames_of(r["end"], fps)
        if src_out <= src_in:
            errors.append(f"range {k}: end {r['end']} is not after start {r['start']}")
            continue
        if src_in < 0 or src_out > total:
            errors.append(
                f"range {k}: [{r['start']}, {r['end']}] is outside the main "
                f"source (0-{duration:.3f}s)"
            )
            continue
        ranges.append(
            {
                "edl_index": k,
                "section": str(r.get("section") or ""),
                "start": r["start"],
                "end": r["end"],
                "lock": bool(r.get("lock")),
                "src_in": src_in,
                "src_out": src_out,
            }
        )
    return errors, ranges


def judge_edge(kind, frame, fps, silences, index, cuts):
    """("error"|"warning", text) for one edge, or None when it is fine."""
    t = frame / fps
    span = silences.containing(t)
    if span:
        window, _ = edge_window(kind, span, fps, cuts)
        if window is None:
            return "warning", (
                f"sits in a {1000 * (span[1] - span[0]):.0f} ms silence, too short "
                "to pad"
            )
        if window[0] <= frame <= window[1]:
            return None
        if kind == "in":
            pad, tight = span[1] - t, frame > window[1]
            band = f"{cuts['preMin']}-{cuts['preMax']}s before speech"
        else:
            pad, tight = t - span[0], frame < window[0]
            band = f"{cuts['postMin']}-{cuts['postMax']}s after speech"
        text = (
            f"keeps {pad:.3f}s of silence (want {band}, in "
            f"[{window[0] / fps:.3f}, {window[1] / fps:.3f}]s): run `video-edit snap`"
        )
        return ("error" if tight else "warning"), text
    inside = index.containing(t)
    text = "is in continuous speech"
    if inside:
        text += f", inside whisper word {_label(inside)}"
    near = silences.near(t, cuts["reach"])
    if near:
        text += f"; a silence is at [{near[0][0]:.3f}, {near[0][1]:.3f}]s (`video-edit snap`)"
    else:
        text += "; review it with `video-edit strip`"
    return "warning", text


def check_edges(ranges, index, silences, fps, cuts):
    """Range edges against silences; locked ranges only warn."""
    errors, warnings = [], []
    for r in ranges:
        k = r["edl_index"]
        t0, t1 = r["src_in"] / fps, r["src_out"] / fps
        if not index.within(t0, t1):
            errors.append(f"range {k} [{t0:.3f}, {t1:.3f}] keeps no words")
        for name, kind, frame in (("start", "in", r["src_in"]), ("end", "out", r["src_out"])):
            verdict = judge_edge(kind, frame, fps, silences, index, cuts)
            if verdict is None:
                continue
            level, text = verdict
            message = f"range {k} {name} {frame / fps:.3f}s {text}"
            if level == "error" and not r["lock"]:
                errors.append(message)
            else:
                warnings.append(message)
    return errors, warnings


def check_overlaps(ranges):
    errors, warnings = [], []
    by_src = sorted(ranges, key=lambda r: r["src_in"])
    for a, b in zip(by_src, by_src[1:]):
        if b["src_in"] < a["src_out"]:
            errors.append(
                f"ranges {a['edl_index']} and {b['edl_index']} overlap in the "
                f"source ([{a['start']}, {a['end']}] and [{b['start']}, {b['end']}])"
            )
    for a, b in zip(ranges, ranges[1:]):
        if a["src_out"] == b["src_in"]:
            warnings.append(
                f"ranges {a['edl_index']} and {b['edl_index']} are contiguous "
                "in the source: merge them"
            )
    return errors, warnings


def assemble(ranges):
    """Copies of `ranges` in output order with rec_in/rec_out; total frames."""
    out, rec = [], 0
    for position, r in enumerate(ranges):
        n = r["src_out"] - r["src_in"]
        out.append({**r, "position": position, "rec_in": rec, "rec_out": rec + n})
        rec += n
    return out, rec


def locate(assembled, src_frame):
    """(range, record frame) showing source frame `src_frame`, or None."""
    for r in assembled:
        if r["src_in"] <= src_frame < r["src_out"]:
            return r, r["rec_in"] + src_frame - r["src_in"]
    return None


def parse_overlays(edl):
    errors, overlays, seen = [], [], set()
    for k, o in enumerate(edl.get("overlays") or []):
        if not isinstance(o, dict):
            errors.append(f"overlay {k}: not an object")
            continue
        slot = o.get("slot")
        if not isinstance(slot, str) or not SLOT_ID.match(slot):
            errors.append(
                f"overlay {k}: slot {slot!r} must be letters, digits, - or _ "
                "(it names folders and files)"
            )
            continue
        if slot in seen:
            errors.append(f"overlay {k}: slot {slot} is used twice")
            continue
        seen.add(slot)
        lead = o.get("lead", 0.0)
        if not (_num(o.get("anchor")) and _num(lead) and _num(o.get("duration"))):
            errors.append(f"overlay {slot}: needs numeric anchor, lead and duration")
            continue
        if lead < 0 or o["duration"] <= 0:
            errors.append(f"overlay {slot}: lead must be >= 0 and duration > 0")
            continue
        overlays.append(
            {
                "slot": slot,
                "anchor": o["anchor"],
                "lead": lead,
                "duration": o["duration"],
                "reason": str(o.get("reason") or ""),
            }
        )
    return errors, overlays


def place_overlays(overlays, assembled, fps, total):
    """Overlay windows on the output: rec_in, frames, rec_out."""
    errors, placed = [], []
    for o in overlays:
        hit = locate(assembled, frames_of(o["anchor"], fps))
        if hit is None:
            errors.append(
                f"overlay {o['slot']}: anchor {o['anchor']}s is in a cut, not in "
                "kept output"
            )
            continue
        r, anchor_rec = hit
        n = frames_of(o["duration"], fps)
        rec_in = anchor_rec - frames_of(o["lead"], fps)
        rec_out = rec_in + n
        if rec_in < 0 or rec_out > total:
            errors.append(
                f"overlay {o['slot']}: window {rec_in / fps:.3f}-{rec_out / fps:.3f}s "
                f"falls outside the {total / fps:.3f}s output"
            )
            continue
        placed.append(
            {
                **o,
                "anchor_rec": anchor_rec,
                "rec_in": rec_in,
                "rec_out": rec_out,
                "frames": n,
                "section": r["section"],
            }
        )
    placed.sort(key=lambda o: o["rec_in"])
    for a, b in zip(placed, placed[1:]):
        if b["rec_in"] < a["rec_out"]:
            errors.append(f"overlays {a['slot']} and {b['slot']} overlap on V3")
    return errors, placed


def validate(edl, words, silences, fps, duration, cuts=None):
    """Everything `build` and `slots` refuse to work from, plus warnings.

    Returns {"errors", "warnings", "ranges" (assembled, all sections),
    "total", "overlays" (placed on the full output)}.
    """
    cuts = {**CUT_DEFAULTS, **(cuts or {})}
    errors, ranges = parse_ranges(edl, fps, duration)
    warnings = []
    e, w = check_edges(ranges, Words(words), silences, fps, cuts)
    errors += e
    warnings += w
    e, w = check_overlaps(ranges)
    errors += e
    warnings += w
    assembled, total = assemble(ranges)
    e, overlays = parse_overlays(edl)
    errors += e
    e, placed = place_overlays(overlays, assembled, fps, total)
    errors += e
    for o in placed:
        section = o["section"]
        span = [x for x in assembled if x["section"] == section]
        if not (span[0]["rec_in"] <= o["rec_in"] and o["rec_out"] <= span[-1]["rec_out"]):
            warnings.append(
                f"overlay {o['slot']} crosses the edge of section "
                f"{section or '(none)'}; a section build can't place it"
            )
    return {
        "errors": errors,
        "warnings": warnings,
        "ranges": assembled,
        "total": total,
        "overlays": placed,
    }


def snap_edge(kind, t, fps, silences, cuts):
    """(new frame, status, silence) for one proposed edge.

    status: "ok" (already in band, left alone), "moved", "short" (silence too short to
    pad; edge put at its middle) or "speech" (no silence within reach;
    left alone for review).
    """
    frame = frames_of(t, fps)
    near = silences.near(frame / fps, cuts["reach"])
    if not near:
        return frame, "speech", None
    span = near[0]
    window, want = edge_window(kind, span, fps, cuts)
    if window is None:
        return frames_of((span[0] + span[1]) / 2, fps), "short", span
    if span[0] - EPS <= frame / fps <= span[1] + EPS and window[0] <= frame <= window[1]:
        return frame, "ok", span
    return min(max(frames_of(want, fps), window[0]), window[1]), "moved", span


def snap(edl, words, silences, fps, cuts=None):
    """(new edl, report): every unlocked range edge moved into its silence."""
    cuts = {**CUT_DEFAULTS, **(cuts or {})}
    index = Words(words)
    new = {**edl, "ranges": [dict(r) for r in edl.get("ranges") or []]}
    report = {"edges": 0, "unchanged": 0, "moved": [], "short": [], "speech": [], "locked": []}
    frames = []
    for k, r in enumerate(new["ranges"]):
        if r.get("lock"):
            report["locked"].append(k)
            frames.append((frames_of(r["start"], fps), frames_of(r["end"], fps)))
            continue
        pair = []
        for kind, key in (("in", "start"), ("out", "end")):
            report["edges"] += 1
            old = frames_of(r[key], fps)
            frame, status, span = snap_edge(kind, r[key], fps, silences, cuts)
            pair.append(frame)
            entry = {
                "range": k,
                "edge": key,
                "from": round(old / fps, 4),
                "to": round(frame / fps, 4),
                "moved_ms": round(1000 * (frame - old) / fps),
                "silence": [round(span[0], 3), round(span[1], 3)] if span else None,
            }
            if status == "ok":
                report["unchanged"] += 1
            elif status == "speech":
                inside = index.containing(old / fps)
                entry["inside_word"] = _label(inside) if inside else None
                report["speech"].append(entry)
            else:
                report[status].append(entry)
        if pair[1] <= pair[0]:
            report.setdefault("collapsed", []).append(k)
            pair = [frames_of(r["start"], fps), frames_of(r["end"], fps)]
        else:
            before = [w["index"] for w in index.within(r["start"], r["end"])]
            after = [w["index"] for w in index.within(pair[0] / fps, pair[1] / fps)]
            if before != after:
                gained = sorted(set(after) - set(before))
                lost = sorted(set(before) - set(after))
                note = []
                if gained:
                    note.append("+" + "".join(index.words[i]["word"] for i in gained))
                if lost:
                    note.append("-" + "".join(index.words[i]["word"] for i in lost))
                report.setdefault("kept_words_changed", []).append(
                    {"range": k, "change": " ".join(note)}
                )
            r["start"], r["end"] = round(pair[0] / fps, 4), round(pair[1] / fps, 4)
        frames.append(tuple(pair))
    # Two ranges that meet in one short silence can cross after snapping;
    # join them at the silence's middle instead.
    order = sorted(range(len(frames)), key=lambda i: frames[i][0])
    for a, b in zip(order, order[1:]):
        if frames[a][1] > frames[b][0] >= frames[a][0]:
            span = silences.containing(frames[b][0] / fps)
            if span and not (new["ranges"][a].get("lock") or new["ranges"][b].get("lock")):
                mid = frames_of((span[0] + span[1]) / 2, fps)
                if frames[a][0] < mid < frames[b][1]:
                    new["ranges"][a]["end"] = new["ranges"][b]["start"] = round(mid / fps, 4)
                    report.setdefault("joined", []).append([a, b])
    moves = [abs(m["moved_ms"]) for m in report["moved"] + report["short"]]
    report["median_move_ms"] = round(statistics.median(moves)) if moves else 0
    report["max_move_ms"] = max(moves) if moves else 0
    return new, report


def select_section(ranges, section):
    """Ranges of one section (all when None), re-assembled from frame 0."""
    if section is None:
        return assemble(ranges)
    chosen = [r for r in ranges if r["section"] == section]
    if not chosen:
        sections = sorted({r["section"] for r in ranges})
        raise UsageError(f"no ranges in section {section!r} (have {sections})")
    return assemble(chosen)


def kept_words(assembled, words, fps):
    """Kept words in output order with output times (seconds)."""
    index = Words(words)
    out = []
    for r in assembled:
        t0, t1 = r["src_in"] / fps, r["src_out"] / fps
        base = r["rec_in"] / fps - t0
        kept = index.within(t0, t1)
        for j, w in enumerate(kept):
            out.append(
                {
                    "i": len(out),
                    "src_index": w["index"],
                    "word": w["word"],
                    "start": w["start"],
                    "end": w["end"],
                    "out_start": round(max(w["start"], t0) + base, 6),
                    "out_end": round(min(w["end"], t1) + base, 6),
                    "range": r["position"],
                    "section": r["section"],
                    "cut_before": j == 0,
                    "cut_after": j == len(kept) - 1,
                }
            )
    return out


def camera_items(assembled, camera, fps):
    """V2 items mirroring every range; camera frame = main frame - offset."""
    warnings, items = [], []
    base = int(camera["offset_frames"])
    changes = sorted(
        (frames_of(c["at"], fps), int(c["offset_frames"]))
        for c in camera.get("offset_changes") or []
    )

    def offset_at(frame):
        offset = base
        for at, value in changes:
            if frame >= at:
                offset = value
        return offset

    for r in assembled:
        cuts = [r["src_in"]]
        cuts += [at for at, _ in changes if r["src_in"] < at < r["src_out"]]
        cuts.append(r["src_out"])
        for a, b in zip(cuts, cuts[1:]):
            offset = offset_at(a)
            cam_in, cam_out = a - offset, b - offset
            lo, hi = max(cam_in, 0), min(cam_out, camera["frames"])
            if hi <= lo:
                warnings.append(
                    f"range {r['edl_index']}: camera has no footage for main "
                    f"frames {a}-{b}; V2 left empty there"
                )
                continue
            if (lo, hi) != (cam_in, cam_out):
                warnings.append(
                    f"range {r['edl_index']}: camera footage covers only "
                    f"{hi - lo} of {cam_out - cam_in} frames; V2 trimmed"
                )
            rec_in = r["rec_in"] + (a - r["src_in"]) + (lo - cam_in)
            items.append(
                {
                    "source": "camera",
                    "src_in": lo,
                    "src_out": hi,
                    "rec_in": rec_in,
                    "rec_out": rec_in + hi - lo,
                    "range": r["position"],
                }
            )
    return items, warnings
