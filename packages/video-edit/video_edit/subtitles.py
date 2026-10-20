"""`words` (kept words in output order) and `srt` (cues to a checked SRT)."""

from difflib import SequenceMatcher
from pathlib import Path
import re

from . import transcript
from .common import UsageError, read_json, safe_name
from .context import Edit
from .timeline import kept_words

PHRASE_GAP = 0.3
SUB_DEFAULTS = {
    "maxChars": 17,
    "minDuration": 0.7,
    "maxDuration": 7.0,
    "linger": 0.3,
    "bridgeGap": 0.5,
}


def plan_words(root, version=None, section=None):
    plan = root.plan(version)
    edit = Edit(root)
    words = kept_words(plan["ranges"], edit.words, plan["fps"])
    if section is not None:
        words = [w for w in words if w["section"] == section]
        if not words:
            raise UsageError(f"no kept words in section {section!r}")
    return plan, edit, words


def clock(t):
    minutes, centis = divmod(round(max(t, 0.0) * 100), 6000)
    return f"{minutes:02d}:{centis // 100:02d}.{centis % 100:02d}"


def render_words(plan, words):
    lines = [
        f"# plan v{plan['version']} ({plan['timeline']}): {len(words)} kept words. "
        "Each line: index of its first piece, output time, pieces split by |; "
        "the k-th piece is word index+k.",
    ]
    phrase = []

    def flush():
        if phrase:
            text = "|".join(w["word"] for w in phrase)
            lines.append(f"{phrase[0]['i']:<6} {clock(phrase[0]['out_start'])}  {text}")
            phrase.clear()

    for w in words:
        if w["cut_before"]:
            flush()
            r = plan["ranges"][w["range"]]
            lines.append(
                f"## cut {w['range']} · {r['section'] or '-'} · "
                f"{clock(r['rec_in'] / plan['fps'])}"
            )
        elif phrase and w["out_start"] - phrase[-1]["out_end"] >= PHRASE_GAP:
            flush()
        phrase.append(w)
    flush()
    return "\n".join(lines) + "\n"


def run_words(root, version=None, section=None, as_json=False):
    plan, _, words = plan_words(root, version, section)
    if as_json:
        return 0, {"version": plan["version"], "words": words}
    return 0, render_words(plan, words)


def apply_glossary(text, glossary):
    for wrong, right in sorted((glossary or {}).items(), key=lambda kv: -len(kv[0])):
        text = re.sub(re.escape(wrong), right, text, flags=re.I)
    return text


def stamp(seconds):
    ms = int(round(seconds * 1000))
    hours, ms = divmod(ms, 3_600_000)
    minutes, ms = divmod(ms, 60_000)
    secs, ms = divmod(ms, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"


def tc_seconds(tc, fps):
    parts = [int(x) for x in re.split(r"[:;]", tc)]
    if len(parts) != 4:
        raise UsageError(f"timecode {tc!r} is not HH:MM:SS:FF")
    h, m, s, f = parts
    return h * 3600 + m * 60 + s + f / fps


def build_cues(cues, words, settings, glossary):
    """(timed cues, errors, warnings) for cues over `words` (the coverage set)."""
    errors, warnings = [], []
    if not isinstance(cues, list) or not cues:
        return [], ["cues must be a non-empty list"], []
    first, last = words[0]["i"], words[-1]["i"]
    by_i = {w["i"]: w for w in words}
    expected = first
    timed = []
    for n, cue in enumerate(cues):
        try:
            a, b, text = int(cue["from"]), int(cue["to"]), str(cue["text"])
        except (KeyError, TypeError, ValueError):
            errors.append(f"cue {n}: needs integer from/to and text")
            continue
        if a != expected:
            if a > expected:
                errors.append(f"cue {n}: words {expected}-{a - 1} are in no cue")
            else:
                errors.append(f"cue {n}: starts at word {a}, overlapping the previous cue")
        if b < a or a not in by_i or b not in by_i:
            errors.append(f"cue {n}: from {a} to {b} is not a range of kept words {first}-{last}")
            expected = max(expected, b + 1)
            continue
        expected = b + 1
        text = apply_glossary(text.strip(), glossary)
        if not text:
            errors.append(f"cue {n}: empty text")
        spoken = transcript.join(by_i[i]["word"] for i in range(a, b + 1))
        heard = transcript.units(apply_glossary(spoken, glossary))
        written = transcript.units(text)
        if heard and SequenceMatcher(None, heard, written, autojunk=False).ratio() < 0.5:
            warnings.append(
                f"cue {n}: text {text!r} differs a lot from words {a}-{b} "
                f"({spoken!r}); check from/to"
            )
        for line in text.split("\n"):
            width = transcript.display_width(line)
            if width > settings["maxChars"]:
                errors.append(
                    f"cue {n}: line {line!r} is {width:g} wide, max {settings['maxChars']}"
                )
        timed.append(
            {"n": n, "from": a, "to": b, "text": text, "start": by_i[a]["out_start"], "end": by_i[b]["out_end"]}
        )
    if expected <= last:
        errors.append(f"words {expected}-{last} are in no cue")
    for cue, nxt in zip(timed, timed[1:] + [None]):
        end = cue["end"]
        if nxt is not None:
            gap = nxt["start"] - end
            end = nxt["start"] if gap < settings["bridgeGap"] else end + settings["linger"]
        else:
            end += settings["linger"]
        cue["end"] = max(end, cue["start"])
        duration = cue["end"] - cue["start"]
        if duration < settings["minDuration"] - 1e-9:
            errors.append(
                f"cue {cue['n']}: shows {duration:.2f}s, min {settings['minDuration']}s; "
                "merge it with a neighbour"
            )
        if duration > settings["maxDuration"] + 1e-9:
            errors.append(
                f"cue {cue['n']}: shows {duration:.2f}s, max {settings['maxDuration']}s; split it"
            )
    return timed, errors, warnings


def render_srt(timed, offset):
    blocks = []
    for k, cue in enumerate(timed, 1):
        blocks.append(
            f"{k}\n{stamp(offset + cue['start'])} --> {stamp(offset + cue['end'])}\n{cue['text']}\n"
        )
    return "\n".join(blocks)


def run_srt(root, cues_path, output=None, version=None, section=None, start_tc=None):
    plan, edit, words = plan_words(root, version, section)
    settings = {**SUB_DEFAULTS, **(edit.spec.get("subtitles") or {})}
    cues = read_json(cues_path)
    timed, errors, warnings = build_cues(cues, words, settings, edit.spec.get("glossary"))
    if errors:
        return 1, {"ok": False, "errors": errors, "warnings": warnings}
    tc = start_tc or plan.get("start_timecode") or "01:00:00:00"
    offset = tc_seconds(tc, plan["fps"])
    if output is None:
        middle = f"_{section}" if section else ""
        output = root / "subtitles" / f"{safe_name(plan['name'])}{middle}_v{plan['version']}.srt"
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_srt(timed, offset), encoding="utf-8")
    return 0, {
        "ok": True,
        "srt": root.rel(output),
        "cues": len(timed),
        "start_timecode": tc,
        "first": stamp(offset + timed[0]["start"]),
        "last": stamp(offset + timed[-1]["end"]),
        "warnings": warnings,
        "insert": "the user inserts this SRT by hand in Resolve (Insert using "
        "timecode); never place it through the API",
    }
