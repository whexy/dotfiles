"""`verify-timeline` (plan vs Resolve's OTIO readback) and `verify-audio`."""

import bisect
from difflib import SequenceMatcher
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote
import wave

from . import silence, transcript
from .common import (
    MediaError,
    NoKeyError,
    TranscribeError,
    UsageError,
    eprint,
    read_json,
    write_json,
)
from .context import Edit
from .timeline import kept_words

# OTIO is parsed by hand (OpenTimelineIO is not in nixpkgs) from its
# documented JSON: Timeline.1 > Stack.1 > Track.1 > Clip.1/Clip.2/Gap.1,
# times as RationalTime {value, rate} and TimeRange {start_time, duration}.
# What Resolve 21 writes has not been checked against a live export yet,
# so unknown schemas and missing fields are tolerated rather than fatal.


def _schema(obj):
    return (obj.get("OTIO_SCHEMA") or "").split(".")[0] if isinstance(obj, dict) else ""


def _frames(rt, fps):
    if not isinstance(rt, dict):
        return None
    rate = float(rt.get("rate") or fps)
    return int(round(float(rt.get("value", 0)) * fps / rate))


def _timeline(data):
    if _schema(data) == "Timeline":
        return data
    for child in (data.get("children") or []) if isinstance(data, dict) else []:
        found = _timeline(child)
        if found:
            return found
    return None


def _basename(url):
    path = unquote(url or "").replace("\\", "/")
    return path.rstrip("/").rsplit("/", 1)[-1]


def _reference(clip):
    refs = clip.get("media_references")
    if isinstance(refs, dict) and refs:
        key = clip.get("active_media_reference_key") or "DEFAULT_MEDIA"
        return refs.get(key) or next(iter(refs.values()))
    return clip.get("media_reference") or {}


def parse_otio(data, fps):
    """{"name", "global_start", "tracks": {"V1": [items]}, "markers"}."""
    tl = _timeline(data)
    if tl is None:
        raise UsageError("no Timeline in the OTIO file")
    tracks, counts, markers = {}, {"V": 0, "A": 0}, []
    for m in tl.get("markers") or []:
        markers.append(m)
    stack = tl.get("tracks") or {}
    markers += stack.get("markers") or []
    for track in stack.get("children") or []:
        if _schema(track) not in ("Track", "Sequence"):
            continue
        prefix = "A" if str(track.get("kind", "Video")).lower().startswith("a") else "V"
        counts[prefix] += 1
        items, pos = [], 0
        for child in track.get("children") or []:
            kind = _schema(child)
            if kind == "Transition":
                continue
            rng = child.get("source_range") or {}
            duration = _frames(rng.get("duration"), fps) or 0
            item = {"kind": kind.lower() or "unknown", "rec_in": pos, "rec_out": pos + duration}
            if kind == "Clip":
                ref = _reference(child)
                start = _frames(rng.get("start_time"), fps) or 0
                base = _frames((ref.get("available_range") or {}).get("start_time"), fps) or 0
                src_in = start - base if start >= base else start
                item.update(
                    name=child.get("name") or "",
                    file=_basename(ref.get("target_url")) or child.get("name") or "",
                    src_in=src_in,
                    src_out=src_in + duration,
                )
            items.append(item)
            pos += duration
        tracks[f"{prefix}{counts[prefix]}"] = items
    marker_frames = sorted(
        f
        for f in (_frames((m.get("marked_range") or {}).get("start_time"), fps) for m in markers)
        if f is not None
    )
    return {
        "name": tl.get("name"),
        "global_start": _frames(tl.get("global_start_time"), fps),
        "tracks": tracks,
        "markers": marker_frames,
    }


def _expected_file(plan, item):
    if item["source"] == "broll":
        return Path(item["file"]).name
    return plan["sources"][item["source"]]["file_name"]


def _describe(item):
    return (
        f"{item['file']} src {item['src_in']}-{item['src_out']} "
        f"at {item['rec_in']}-{item['rec_out']}"
    )


def diff_plan(plan, readback, limit=40):
    """Every way the readback differs from the plan, frame by frame."""
    fps = plan["fps"]
    problems, summary = [], {}
    found = readback["tracks"]
    leftovers = {}
    for key, planned in plan["tracks"].items():
        expected = [{**i, "file": _expected_file(plan, i)} for i in planned]
        actual_all = found.get(key, [])
        actual = [i for i in actual_all if i["kind"] == "clip"]
        summary[key] = {"expected": len(expected), "found": len(actual)}
        if not expected and not actual:
            continue
        if key not in found:
            problems.append(f"{key}: track missing in the readback ({len(expected)} items planned)")
            continue
        for gap in (i for i in actual_all if i["kind"] == "gap"):
            if any(e["rec_in"] < gap["rec_out"] and gap["rec_in"] < e["rec_out"] for e in expected):
                problems.append(
                    f"{key}: {gap['rec_out'] - gap['rec_in']}-frame gap at "
                    f"{gap['rec_in']} ({gap['rec_in'] / fps:.3f}s) where the plan has media"
                )
        ekeys = [(e["file"].lower(), e["src_in"]) for e in expected]
        akeys = [(a["file"].lower(), a["src_in"]) for a in actual]
        matcher = SequenceMatcher(None, ekeys, akeys, autojunk=False)
        missing, extra = [], []
        for op, i1, i2, j1, j2 in matcher.get_opcodes():
            pairs = list(zip(range(i1, i2), range(j1, j2))) if op in ("equal", "replace") else []
            for i, j in pairs:
                e, a = expected[i], actual[j]
                notes = []
                if a["file"].lower() != e["file"].lower():
                    notes.append(f"source {a['file']}")
                if a["src_in"] != e["src_in"]:
                    notes.append(f"src_in {a['src_in'] - e['src_in']:+d}")
                if a["rec_in"] != e["rec_in"]:
                    notes.append(f"rec_in {a['rec_in'] - e['rec_in']:+d}")
                length = (a["rec_out"] - a["rec_in"]) - (e["rec_out"] - e["rec_in"])
                if length:
                    notes.append(f"length {length:+d}")
                if notes:
                    problems.append(
                        f"{key} item {i} ({_describe(e)}): found {_describe(a)} [{', '.join(notes)}]"
                    )
            if op in ("delete", "replace"):
                missing += [expected[i] for i in range(i1 + len(pairs), i2)]
            if op in ("insert", "replace"):
                extra += [actual[j] for j in range(j1 + len(pairs), j2)]
        for e in missing:
            problems.append(f"{key}: missing {_describe(e)}")
        leftovers[key] = extra
    for key, items in found.items():
        if key not in plan["tracks"]:
            leftovers[key] = [i for i in items if i["kind"] == "clip"]
    planned_all = [(k, i) for k, v in plan["tracks"].items() for i in v]
    for key, extra in leftovers.items():
        for a in extra:
            home = next(
                (
                    k
                    for k, i in planned_all
                    if k != key
                    and i["rec_in"] == a["rec_in"]
                    and i["src_in"] == a["src_in"]
                    and _expected_file(plan, i).lower() == a["file"].lower()
                ),
                None,
            )
            where = f" (belongs on {home})" if home else ""
            problems.append(f"{key}: unexpected {_describe(a)}{where}")
    ends = [i["rec_out"] for items in found.values() for i in items if i["kind"] == "clip"]
    if ends and max(ends) != plan["duration_frames"]:
        problems.append(
            f"timeline ends at frame {max(ends)}, plan {plan['duration_frames']} "
            f"({(max(ends) - plan['duration_frames']):+d})"
        )
    notes = []
    start = readback["global_start"]
    if start is not None:
        h, m, s, f = (int(x) for x in plan["start_timecode"].replace(";", ":").split(":"))
        want = ((h * 60 + m) * 60 + s) * fps + f
        if start != want:
            notes.append(
                f"timeline starts at frame {start}, not {plan['start_timecode']}: "
                "pass the real start to `video-edit srt --start-tc`"
            )
    if len(readback["markers"]) != len(plan["markers"]):
        notes.append(f"{len(readback['markers'])} markers read back, {len(plan['markers'])} planned")
    more = max(0, len(problems) - limit)
    return {
        "ok": not problems,
        "tracks": summary,
        "problems": problems[:limit] + ([f"... and {more} more"] if more else []),
        "notes": notes,
    }


def run_verify_timeline(root, version=None, otio=None):
    plan = root.plan(version)
    path = Path(otio) if otio else root / "verify" / f"readback_v{plan['version']}.otio"
    if not path.exists():
        raise UsageError(
            f"no readback at {root.rel(path)}: run `video-edit readback-script` "
            "and its script in Resolve first"
        )
    readback = parse_otio(read_json(path), plan["fps"])
    report = diff_plan(plan, readback)
    return (0 if report["ok"] else 1), {
        "version": plan["version"],
        "timeline": plan["timeline"],
        "otio": root.rel(path),
        **report,
    }


def assemble_audio(source_wav, plan, out):
    """The plan's V1/A1 cut list applied to a mono WAV, sample-exact."""
    fps = plan["fps"]
    with wave.open(str(source_wav), "rb") as src:
        rate, width, frames = src.getframerate(), src.getsampwidth(), src.getnframes()
        partial = out.with_name(f".{out.name}.partial.wav")
        with wave.open(str(partial), "wb") as dst:
            dst.setnchannels(1)
            dst.setsampwidth(width)
            dst.setframerate(rate)
            for item in plan["tracks"]["A1"]:
                n = round(item["rec_out"] * rate / fps) - round(item["rec_in"] * rate / fps)
                start = round(item["src_in"] * rate / fps)
                src.setpos(min(start, frames))
                data = src.readframes(n)
                dst.writeframes(data + b"\0" * (n * width - len(data)))
    partial.replace(out)
    return out


def _owners(words, start_key):
    units, owners = [], []
    for w in words:
        for u in transcript.units(w["word"]):
            units.append(u)
            owners.append((w, w[start_key]))
    return units, owners


def diff_speech(expected, heard, cut_times, near=1.0):
    """Clipped, missing, leaked or doubled speech, each tied to a cut.

    Repeats of a neighbouring piece are tolerated in either direction:
    whisper drops repeated words on its own.
    """
    exp_units, exp_owner = _owners(expected, "out_start")
    got_units, got_owner = _owners(heard, "start")
    matcher = SequenceMatcher(None, exp_units, got_units, autojunk=False)
    issues, repeats = [], 0

    def nearest(t):
        if not cut_times:
            return None, None
        i = bisect.bisect_left(cut_times, t)
        best = min(
            (k for k in (i - 1, i) if 0 <= k < len(cut_times)),
            key=lambda k: abs(cut_times[k] - t),
        )
        return best, cut_times[best]

    def repeated(units, seq, i1, i2):
        n = i2 - i1
        return seq[max(0, i1 - n) : i1] == units or seq[i2 : i2 + n] == units

    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            continue
        lost, gained = exp_units[i1:i2], got_units[j1:j2]
        if op == "delete" and repeated(lost, exp_units, i1, i2):
            repeats += 1
            continue
        if op == "insert" and (
            repeated(gained, got_units, j1, j2) or repeated(gained, exp_units, i1, i1)
        ):
            repeats += 1
            continue
        if op == "replace" and len(lost) == len(gained):
            kind = "variant"
        elif op == "insert":
            kind = "extra"
        elif op == "delete":
            kind = "missing"
        else:
            kind = "changed"
        t = exp_owner[i1][1] if i1 < len(exp_owner) else got_owner[j1][1]
        if op == "insert":
            t = got_owner[j1][1]
        cut, at = nearest(t)
        close = at is not None and abs(t - at) <= near
        if close and kind == "missing":
            kind = "clipped"
        if close and kind == "extra":
            kind = "leaked"
        issues.append(
            {
                "kind": kind,
                "expected": "".join(lost),
                "heard": "".join(gained),
                "out_time": round(t, 2),
                "cut": cut,
                "cut_time": None if at is None else round(at, 2),
                "at_cut": close and kind != "variant",
            }
        )
    ratio = matcher.ratio()
    return issues, repeats, ratio


def _plan_sha(plan):
    return hashlib.sha256(json.dumps(plan["tracks"]["A1"]).encode()).hexdigest()[:16]


def run_verify_audio(root, version=None):
    plan = root.plan(version)
    edit = Edit(root)
    n = plan["version"]
    audio = root / "verify" / f"audio_v{n}.wav"
    heard_path = root / "verify" / f"audio_v{n}.transcript.json"
    meta_path = root / "verify" / f"audio_v{n}.meta.json"
    sha = _plan_sha(plan)
    cached = (
        heard_path.exists() and meta_path.exists() and read_json(meta_path).get("plan") == sha
    )
    if not cached:
        source = silence.audio_cache(root, Path(edit.main["path"]))
        audio.parent.mkdir(parents=True, exist_ok=True)
        assemble_audio(source, plan, audio)
        eprint(f"transcribing {root.rel(audio)} (cut audio of v{n})")
        try:
            result = subprocess.run(
                ["transcribe", str(audio), "--format", "json", "-o", str(heard_path), "--yes"],
                capture_output=True,
                text=True,
            )
        except FileNotFoundError as err:
            raise TranscribeError("transcribe is not on PATH") from err
        if result.returncode == 5:
            raise NoKeyError(
                "transcribe has no OpenAI key (exit 5); ask the user to set "
                "secrets/openai-api-key.age with agenix and rebuild, then rerun. "
                f"The cut audio is ready at {root.rel(audio)}"
            )
        if result.returncode != 0:
            tail = " ".join(result.stderr.strip().splitlines()[-3:])
            raise TranscribeError(f"transcribe failed ({result.returncode}): {tail}")
        write_json(meta_path, {"plan": sha})
    _, heard = transcript.load(heard_path)
    expected = kept_words(plan["ranges"], edit.words, plan["fps"])
    # Cut k starts range k, and the last one ends the output: the head and tail
    # trim speech like any other cut.
    fps = plan["fps"]
    cut_times = [r["rec_in"] / fps for r in plan["ranges"]] + [plan["duration_frames"] / fps]
    issues, repeats, ratio = diff_speech(expected, heard, cut_times)
    flagged = {}
    for issue in issues:
        if issue["at_cut"]:
            flagged.setdefault(issue["cut"], []).append(issue)
    if not heard and expected:
        raise MediaError("the cut audio transcribed to nothing; is the main audio silent?")
    return (1 if flagged else 0), {
        "ok": not flagged,
        "version": n,
        "audio": root.rel(audio),
        "transcript": root.rel(heard_path),
        "cached": cached,
        "match_ratio": round(ratio, 3),
        "flagged_cuts": [
            {
                "cut": cut,
                "at": round(cut_times[cut], 2),
                "issues": [f"{i['kind']}: expected {i['expected']!r} heard {i['heard']!r}" for i in found],
                "look": f"video-edit strip --cut {cut} --version {n}",
            }
            for cut, found in sorted(flagged.items())
        ],
        "tolerated_repeats": repeats,
        "far_from_cuts": sum(1 for i in issues if not i["at_cut"]),
    }
