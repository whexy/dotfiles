"""Detected silences in the main source: the authority for cut edges.

whisper-1 word edges are not: on the user's footage most "words" are
single hanzi with zero gaps, and 33 of 59 cut edges the user approved
fall inside a whisper word, 21 of them in real silence. Silences come
from ffmpeg `silencedetect` at the measured noise floor + 9 dB (the
mic's floor is about -44.5 dB and pauses sit at -38 to -42 dB).
"""

import bisect
from pathlib import Path
import re

from .common import eprint, read_json, write_json
from .media import run

SAMPLE_RATE = 16000
DEFAULTS = {"thresholdDb": None, "floorOffsetDb": 9, "fallbackDb": -35, "minDuration": 0.05}


def settings(spec):
    return {**DEFAULTS, **(spec.get("silence") or {})}


def audio_cache(root, source):
    """16 kHz mono WAV of a source, extracted once into transcripts/."""
    source = Path(source)
    wav = root / "transcripts" / f"{source.stem}.16k.wav"
    meta = wav.with_suffix(".json")
    stat = source.stat()
    key = {"source": str(source), "size": stat.st_size, "mtime_ns": stat.st_mtime_ns}
    if wav.exists() and meta.exists() and read_json(meta) == key:
        return wav
    eprint(f"extracting audio of {source.name} (once)")
    wav.parent.mkdir(parents=True, exist_ok=True)
    partial = wav.with_name(f".{wav.name}.partial.wav")
    run(
        [
            "ffmpeg", "-y", "-v", "error", "-i", str(source), "-vn", "-ac", "1",
            "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", str(partial),
        ]
    )
    partial.replace(wav)
    write_json(meta, key)
    return wav


def noise_floor(wav):
    """ffmpeg astats' overall noise floor in dBFS, or None."""
    log = run(
        [
            "ffmpeg", "-hide_banner", "-nostats", "-i", str(wav), "-af",
            "astats=measure_perchannel=none:measure_overall=Noise_floor",
            "-f", "null", "-",
        ]
    ).stderr
    m = re.search(r"Noise floor dB: (-?[\d.]+|-inf)", log)
    if not m or m.group(1) == "-inf":
        return None
    return float(m.group(1))


def detect(wav, threshold_db, min_duration, duration=None):
    log = run(
        [
            "ffmpeg", "-hide_banner", "-nostats", "-i", str(wav), "-af",
            f"silencedetect=noise={threshold_db}dB:d={min_duration}",
            "-f", "null", "-",
        ]
    ).stderr
    starts = [max(0.0, float(x)) for x in re.findall(r"silence_start: (-?[\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    if len(ends) < len(starts) and duration is not None:
        ends.append(duration)
    return [[round(s, 4), round(e, 4)] for s, e in zip(starts, ends) if e > s]


def load(root, main, spec, refresh=False):
    """Cached silences of the main source, detected when missing or stale."""
    conf = settings(spec)
    source = Path(main["path"])
    path = root / "transcripts" / f"{source.stem}.silences.json"
    if path.exists() and not refresh:
        data = read_json(path)
        stat = source.stat() if source.exists() else None
        fresh = data.get("settings") == conf and (
            stat is None
            or (data.get("size"), data.get("mtime_ns")) == (stat.st_size, stat.st_mtime_ns)
        )
        if fresh:
            return data
    wav = audio_cache(root, source)
    floor = noise_floor(wav)
    if conf["thresholdDb"] is not None:
        threshold, origin = conf["thresholdDb"], "spec.json silence.thresholdDb"
    elif floor is not None:
        threshold = round(floor + conf["floorOffsetDb"], 2)
        origin = f"noise floor {floor:.2f} dB + {conf['floorOffsetDb']} dB"
    else:
        threshold, origin = conf["fallbackDb"], "fallback (no noise floor measured)"
    eprint(f"detecting silences at {threshold} dB, >= {conf['minDuration']} s")
    spans = detect(wav, threshold, conf["minDuration"], main.get("duration"))
    stat = source.stat()
    data = {
        "source": str(source),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "settings": conf,
        "noise_floor_db": floor,
        "threshold_db": threshold,
        "threshold_from": origin,
        "min_duration": conf["minDuration"],
        "count": len(spans),
        "silences": spans,
    }
    write_json(path, data)
    return data


class Silences:
    def __init__(self, spans):
        self.spans = sorted((float(s), float(e)) for s, e in spans)
        self.starts = [s for s, _ in self.spans]

    def containing(self, t, eps=1e-6):
        i = bisect.bisect_right(self.starts, t + eps) - 1
        if i >= 0 and self.spans[i][1] >= t - eps:
            return self.spans[i]
        return None

    def near(self, t, reach):
        """Spans within `reach` seconds of t, nearest first."""
        # Spans don't overlap, so only the one just before the window can
        # reach into it from the left.
        lo = bisect.bisect_left(self.starts, t - reach)
        hi = bisect.bisect_right(self.starts, t + reach)
        found = []
        for s, e in self.spans[max(0, lo - 1) : hi]:
            distance = 0.0 if s <= t <= e else min(abs(t - s), abs(t - e))
            if distance <= reach + 1e-9:
                found.append((distance, (s, e)))
        return [span for _, span in sorted(found)]
