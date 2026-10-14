#!/usr/bin/env python3
"""Transcribe an audio/video file into an agent-readable, word-timed transcript.

Uses OpenAI `whisper-1`, the only transcription model that returns word
timestamps. The transcript is annotated (per-word gaps, fillers,
repeated word/phrase stumbles, silent stretches without speech) so an
agent can propose video cuts from the transcript alone, reading
individual word errors against the surrounding context. Word edges land
about +/-0.2 s from the real pause edges; treat them as decision
support, not cut points, until they are snapped to detected silence in
the actual edit.

Default output is a compact annotated transcript; `--format json` gives
the full word-level data, and `--from-json` re-renders that data in any
format without the API or ffmpeg. Exit codes: 0 ok, 2 usage (including
a `--from-json` file that is not transcribe JSON), 3 media/ffmpeg, 4 API,
5 missing OPENAI_API_KEY.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.request
import uuid

API_URL = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
AUDIO_FORMATS = {"mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm"}
MAX_FILE = 24 * 1000 * 1000  # API limit is 25 MB; leave multipart headroom
CHUNK_SECONDS = 600.0
# Pauses sit a few dB above the recording's noise floor, which varies by
# mic and room: a USB mic with a -44.5 dB floor has pauses at -38 to -42 dB.
FLOOR_MARGIN_DB = 9.0
SILENCE_FALLBACK_DB = -35.0
# Shorter silences are breaths inside a phrase, which the 0.6 s default
# --pause would not show as a pause either.
SILENCE_MIN = 0.5
# Measurement and detection read the same 16 kHz mono signal, so the
# 800-sample level windows are 50 ms whatever the source format.
ANALYSIS_FORMAT = "aformat=sample_rates=16000:channel_layouts=mono"
# whisper-1 word edges land up to ~0.25 s from the real pause edges, so a
# silence overhanging a word gap by less than this is that gap.
EDGE_SLOP = 0.3
STUMBLE_PIECES = 4
STUMBLE_GAP = 1.5

EXIT_OK, EXIT_USAGE, EXIT_MEDIA, EXIT_API, EXIT_NOKEY = 0, 2, 3, 4, 5

MODEL = "whisper-1"
PRICE_PER_MIN = 0.006

FILLERS_EN = {
    "um", "uh", "uhm", "umm", "uhh", "er", "erm", "hmm", "mm", "mhm",
    "ah", "eh", "like", "basically", "actually", "literally",
}
FILLERS_ZH = {"嗯", "呃", "啊", "那个", "就是", "然后"}


class MediaError(Exception):
    pass


class ApiError(Exception):
    pass


class UsageError(Exception):
    pass


def eprint(*args):
    print("transcribe:", *args, file=sys.stderr)


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        tail = result.stderr.strip().splitlines()[-5:]
        raise MediaError(f"{cmd[0]} failed: {' '.join(tail)}")
    return result


def probe(path):
    out = run(
        [
            "ffprobe", "-v", "error", "-show_entries",
            "stream=codec_type,duration",
            "-show_entries", "format=duration",
            "-of", "json", str(path),
        ]
    ).stdout
    info = json.loads(out)
    streams = info.get("streams", [])
    if not any(s.get("codec_type") == "audio" for s in streams):
        raise MediaError(f"no audio stream in {path}")
    duration = info.get("format", {}).get("duration")
    if duration is None:
        duration = next(
            (s["duration"] for s in streams if s.get("duration")), None
        )
    if duration is None:
        raise MediaError(f"cannot determine duration of {path}")
    return float(duration)


def extract_audio(path, out):
    # 64 kbps mono keeps a 10-minute chunk well under the API file limit
    # while staying transparent for speech recognition.
    run(
        [
            "ffmpeg", "-y", "-v", "error", "-i", str(path),
            "-vn", "-ac", "1", "-ar", "16000", "-c:a", "libmp3lame",
            "-b:a", "64k", str(out),
        ]
    )


def noise_floor(path):
    """5th-percentile 50 ms RMS level of `path` in dBFS, or None.

    astats' own Noise_floor is a minimum, which mp3 artifacts drag to
    -70 dB on a mic whose floor is -44.5 dB; a low percentile of window
    levels tracks the room noise on any codec. A file with over 5%
    digital silence has no finite floor and gets None.
    """
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", str(path), "-af",
            f"{ANALYSIS_FORMAT},asetnsamples=n=800:p=0,"
            "astats=metadata=1:reset=1:measure_perchannel=none:"
            "measure_overall=RMS_level,"
            "ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
            "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    levels = sorted(
        level
        for level in map(float, re.findall(r"RMS_level=(\S+)", result.stdout))
        if not math.isnan(level)
    )
    if result.returncode or not levels:
        return None
    floor = levels[int(0.05 * (len(levels) - 1))]
    return round(floor, 2) if math.isfinite(floor) else None


def silence_settings(path, requested):
    """Detection settings for `path`; `requested` is a dB value or "auto"."""
    floor = None
    if requested == "auto":
        floor = noise_floor(path)
        threshold = (
            SILENCE_FALLBACK_DB
            if floor is None
            else round(floor + FLOOR_MARGIN_DB, 2)
        )
    else:
        threshold = requested
    return {
        "threshold_db": threshold,
        "min_duration": SILENCE_MIN,
        "noise_floor_db": floor,
    }


def detect_silences(path, settings, duration):
    """Sorted [(start, end), ...] silence intervals from ffmpeg silencedetect."""
    result = subprocess.run(
        [
            "ffmpeg", "-v", "info", "-i", str(path), "-af",
            f"{ANALYSIS_FORMAT},silencedetect="
            f"noise={settings['threshold_db']}dB:d={settings['min_duration']}",
            "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    # A silence at t=0 can be reported slightly negative, and one still
    # running at EOF may never get its silence_end.
    spans, start = [], None
    for kind, value in re.findall(r"silence_(start|end): (-?[\d.]+)", result.stderr):
        if kind == "start":
            start = max(0.0, float(value))
        elif start is not None:
            spans.append((start, float(value)))
            start = None
    if start is not None and start < duration:
        spans.append((start, duration))
    return spans


def plan_chunks(duration, silences, target=CHUNK_SECONDS):
    """Split [0, duration] near `target` intervals, at silence midpoints."""
    if duration <= target * 1.2:
        return [(0.0, duration)]
    mids = sorted((s + e) / 2 for s, e in silences if 0 < s < duration)
    cuts, start = [], 0.0
    while duration - start > target * 1.2:
        ideal = start + target
        near = [m for m in mids if abs(m - ideal) <= target * 0.25]
        cut = min(near, key=lambda m: abs(m - ideal)) if near else ideal
        cuts.append((start, cut))
        start = cut
    cuts.append((start, duration))
    return cuts


def split_audio(audio, chunks, workdir):
    files = []
    for i, (start, end) in enumerate(chunks):
        out = workdir / f"chunk-{i:03d}.mp3"
        # Re-encode rather than stream-copy: identical commands for every
        # input and exact boundaries, at negligible cost for speech audio.
        run(
            [
                "ffmpeg", "-y", "-v", "error", "-ss", f"{start:.3f}",
                "-to", f"{end:.3f}", "-i", str(audio),
                "-ac", "1", "-ar", "16000", "-c:a", "libmp3lame",
                "-b:a", "64k", str(out),
            ]
        )
        if out.stat().st_size > MAX_FILE:
            raise MediaError(f"chunk {i} exceeds the API file limit")
        files.append(out)
    return files


def multipart(fields, file_field, filename, data):
    boundary = f"transcribe-{uuid.uuid4().hex}"
    body = bytearray()
    for name, value in fields:
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += f"{value}\r\n".encode()
    body += f"--{boundary}\r\n".encode()
    body += (
        f'Content-Disposition: form-data; name="{file_field}"; '
        f'filename="{filename}"\r\nContent-Type: audio/mpeg\r\n\r\n'
    ).encode()
    body += data
    body += f"\r\n--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def transcribe_chunk(client, path, args):
    fields = [
        ("model", MODEL),
        ("response_format", "verbose_json"),
        ("timestamp_granularities[]", "word"),
        ("timestamp_granularities[]", "segment"),
    ]
    if args.language:
        fields.append(("language", args.language))
    if args.context:
        # Whisper's prompt window is 224 tokens; pass it through untouched
        # rather than silently truncating a glossary the user chose.
        fields.append(("prompt", args.context))
    return client(fields, path.name, path.read_bytes())


def make_client(api_key):
    def call(fields, filename, data):
        delay = 2.0
        last = None
        for _ in range(4):
            body, content_type = multipart(fields, "file", filename, data)
            request = urllib.request.Request(
                f"{API_URL}/audio/transcriptions",
                data=body,
                method="POST",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": content_type,
                },
            )
            try:
                with urllib.request.urlopen(request, timeout=600) as response:
                    return json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as err:
                detail = err.read().decode("utf-8", "replace")[:500]
                if err.code in (429, 500, 502, 503):
                    time.sleep(delay)
                    delay *= 2
                    continue
                raise ApiError(f"HTTP {err.code}: {detail}") from err
            except urllib.error.URLError as err:
                last = err
                time.sleep(delay)
                delay *= 2
        raise ApiError(f"request failed after retries: {last}")

    return call


def norm_key(word):
    return "".join(ch for ch in word.lower() if ch.isalnum())


def is_hanzi(ch):
    return unicodedata.name(ch, "").startswith("CJK UNIFIED IDEOGRAPH")


def repeat_is_stumble(take):
    """Whether saying normalized text `take` twice in a row is a stumble."""
    if not all(map(is_hanzi, take)):
        return True
    # Doubled single hanzi (刚刚, 看看) and 一X一X (一台一台, "one by one")
    # are ordinary reduplication.
    return len(take) > 2 or (len(take) == 2 and take[0] != "一")


def annotate(words):
    """Attach gap_after/filler/stumble to each word dict, in place.

    Both takes of an immediate repeat are marked. Takes are compared as
    joined text of up to STUMBLE_PIECES pieces, because whisper-1 splits
    Chinese into single hanzi (最|后|最|后) and Latin words into subwords
    (sk|ills), not always the same way twice.
    """
    for i, word in enumerate(words):
        word["gap_after"] = (
            round(words[i + 1]["start"] - word["end"], 3)
            if i + 1 < len(words)
            else None
        )
        word["filler"] = is_filler(word["word"])
        word["stumble"] = False
    keys = [norm_key(w["word"]) for w in words]
    spoken = [i for i, key in enumerate(keys) if key]
    for a in range(len(spoken)):
        for n in range(1, STUMBLE_PIECES + 1):
            first = spoken[a : a + n]
            if len(first) < n:
                break
            take = "".join(keys[i] for i in first)
            if not repeat_is_stumble(take):
                continue
            for m in range(1, STUMBLE_PIECES + 1):
                second = spoken[a + n : a + n + m]
                again = "".join(keys[i] for i in second)
                if len(second) < m or not take.startswith(again):
                    break
                if (
                    again == take
                    and words[second[0]]["start"] - words[first[-1]]["end"]
                    < STUMBLE_GAP
                ):
                    for i in first + second:
                        words[i]["stumble"] = True
    return words


def is_filler(word):
    key = norm_key(word)
    return key in FILLERS_EN or word in FILLERS_ZH or key in FILLERS_ZH


def collapse_silences(silences, words):
    """Silences no word gap accounts for: dead air, music, or a pause
    whisper-1 stretched a word over."""
    gaps = [
        (words[i]["end"], words[i + 1]["start"])
        for i in range(len(words) - 1)
        if words[i + 1]["start"] > words[i]["end"]
    ]
    return [
        (s, e)
        for s, e in silences
        if not any(
            s >= gs - EDGE_SLOP and e <= ge + EDGE_SLOP for gs, ge in gaps
        )
    ]


def group_segments(words, pause_min):
    segments, current = [], []
    for word in words:
        current.append(word)
        if word["gap_after"] is None or word["gap_after"] >= pause_min:
            segments.append(current)
            current = []
    if current:
        segments.append(current)
    out = []
    for i, seg in enumerate(segments):
        out.append(
            {
                "index": i,
                "start": seg[0]["start"],
                "end": seg[-1]["end"],
                "pause_before": (
                    round(seg[0]["start"] - segments[i - 1][-1]["end"], 3)
                    if i
                    else round(seg[0]["start"], 3)
                ),
                "text": " ".join(w["word"] for w in seg),
                "flags": [
                    name
                    for name in ("filler", "stumble")
                    if any(w[name] for w in seg)
                ],
                "words": seg,
            }
        )
    return out


def ts(seconds):
    minutes, secs = divmod(max(seconds, 0.0), 60)
    return f"{int(minutes):02d}:{secs:05.2f}"


def render_text(result):
    lines = [
        f"# transcribe {result['source']} "
        f"model={result['model']} duration={result['duration']:.1f}s",
        "# [MM:SS.ss-MM:SS.ss] segments split on pauses; "
        "(pause Xs) = silence before segment",
        "# {word} = filler, {{word}} = stumble (word or phrase said twice; "
        "both takes marked), <pause 1.2s> inline = long pause inside a segment",
        "# whisper-1 text: read word errors against context; word edges "
        "+/-0.2s at pauses, snap cut points to detected silence and add handles",
        "",
    ]
    for seg in result["segments"]:
        body = []
        for word in seg["words"]:
            text = word["word"]
            if word["stumble"]:
                text = "{{" + text + "}}"
            elif word["filler"]:
                text = "{" + text + "}"
            body.append(text)
            if word["gap_after"] is not None and word["gap_after"] >= 1.0:
                body.append(f"<pause {word['gap_after']:.1f}s>")
        pause = (
            f" (pause {seg['pause_before']:.1f}s)"
            if seg["pause_before"] >= 0.05
            else ""
        )
        lines.append(
            f"[{ts(seg['start'])}-{ts(seg['end'])}]{pause} {' '.join(body)}"
        )
    for s, e in result["silences"]:
        lines.append(f"# silence without speech: [{ts(s)}-{ts(e)}] {e - s:.1f}s")
    return "\n".join(lines) + "\n"


def render_srt(segments):
    def stamp(seconds):
        whole = int(seconds)
        hours, rem = divmod(whole, 3600)
        minutes, secs = divmod(rem, 60)
        return f"{hours:02d}:{minutes:02d}:{secs:02d},{int(round((seconds - whole) * 1000)):03d}"

    cues = []
    for i, seg in enumerate(segments, 1):
        cues.append(
            f"{i}\n{stamp(seg['start'])} --> {stamp(seg['end'])}\n{seg['text']}\n"
        )
    return "\n".join(cues)


def render(result, fmt):
    if fmt == "json":
        return json.dumps(result, ensure_ascii=False, indent=2)
    if fmt == "srt":
        return render_srt(result["segments"])
    return render_text(result)


def process(args, client):
    source = Path(args.file)
    if not source.is_file():
        raise MediaError(f"not a file: {source}")
    duration = probe(source)
    suffix = source.suffix.lower().lstrip(".")
    use_direct = suffix in AUDIO_FORMATS and source.stat().st_size <= MAX_FILE

    timings = {"media_seconds": 0.0, "api_seconds": 0.0}
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="transcribe-") as tmp:
        workdir = Path(tmp)
        if use_direct and duration <= CHUNK_SECONDS * 1.2:
            audio = source
        else:
            audio = workdir / "audio.mp3"
            extract_audio(source, audio)
        silence = None if args.no_silence else silence_settings(audio, args.silence_db)
        silences = detect_silences(audio, silence, duration) if silence else []
        chunks = plan_chunks(duration, silences)
        eprint(f"duration {duration:.0f}s, {len(chunks)} chunk(s)")
        if silence:
            floor = silence["noise_floor_db"]
            eprint(
                f"silence threshold {silence['threshold_db']} dB"
                + ("" if floor is None else f" (noise floor {floor} dB)")
            )
        files = [audio] if len(chunks) == 1 else split_audio(audio, chunks, workdir)
        timings["media_seconds"] = round(time.monotonic() - started, 2)

        started = time.monotonic()
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(
                pool.map(lambda f: transcribe_chunk(client, f, args), files)
            )
        timings["api_seconds"] = round(time.monotonic() - started, 2)

    words, languages = [], []
    for (offset, _), timed in zip(chunks, results):
        code = timed.get("language")
        if code and code not in languages:
            languages.append(code)
        words += [
            {
                "word": w.get("word", ""),
                "start": round(offset + w["start"], 3),
                "end": round(offset + w["end"], 3),
            }
            for w in timed.get("words", [])
            if w.get("word")
        ]

    words.sort(key=lambda w: w["start"])
    annotate(words)
    segments = group_segments(words, args.pause)
    return {
        "source": str(source),
        "duration": duration,
        "model": MODEL,
        "languages": languages,
        "estimated_cost_usd": round(duration / 60 * PRICE_PER_MIN, 4),
        "timings": timings,
        "segments": segments,
        "silence": silence,
        "silences": collapse_silences(silences, words),
    }


def load_transcript(path):
    """A `--format json` result, checked for every field rendering reads."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        raise UsageError(f"cannot read transcript {path}: {err}") from err

    def number(value):
        return isinstance(value, (int, float)) and not isinstance(value, bool)

    def word(w):
        return (
            isinstance(w, dict)
            and isinstance(w.get("word"), str)
            and number(w.get("start"))
            and number(w.get("end"))
        )

    try:
        valid = (
            {"source", "model"} <= data.keys()
            and number(data["duration"])
            and all(all(map(word, seg["words"])) for seg in data["segments"])
            and all(len(s) == 2 and all(map(number, s)) for s in data["silences"])
        )
    except (AttributeError, KeyError, TypeError):
        valid = False
    if not valid:
        raise UsageError(f"{path} is not a `transcribe --format json` output")
    return data


def rerender(data, args):
    """Rebuild a loaded result for this run's --pause and --no-silence.

    Only word text and timings are read back; gaps, flags and segments
    are re-derived the way `process` derives them. Stored silences are
    already collapsed against those words, so they carry over as-is.
    """
    words = [
        {"word": w["word"], "start": w["start"], "end": w["end"]}
        for seg in data["segments"]
        for w in seg["words"]
    ]
    annotate(words)
    result = {
        **data,
        "segments": group_segments(words, args.pause),
        "silences": [] if args.no_silence else data["silences"],
    }
    if args.no_silence:
        result["silence"] = None
    return result


def estimate(args):
    duration = probe(Path(args.file))
    print(
        json.dumps(
            {
                "source": args.file,
                "duration_seconds": round(duration, 1),
                "model": MODEL,
                "estimated_cost_usd": round(duration / 60 * PRICE_PER_MIN, 4),
            },
            indent=2,
        )
    )


def silence_db(value):
    if value == "auto":
        return value
    try:
        db = float(value)
    except ValueError:
        db = math.nan
    if not (math.isfinite(db) and db < 0):
        raise argparse.ArgumentTypeError(
            f"expected a negative dBFS number or auto, got {value!r}"
        )
    return db


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        epilog="stdout carries only the transcript; progress goes to stderr. "
        "Exit codes: 0 ok, 2 usage (including a --from-json file that is not "
        "transcribe JSON), 3 media/ffmpeg, 4 API, 5 missing key.",
    )
    parser.add_argument(
        "file",
        help="audio or video file to transcribe (with --from-json: an earlier "
        "--format json output)",
    )
    parser.add_argument(
        "-o", "--output", help="write to this file instead of stdout"
    )
    parser.add_argument(
        "--format", choices=["text", "json", "srt"], default="text",
        help="default text; json includes every word with start/end/gap "
        "and filler/stumble flags",
    )
    parser.add_argument(
        "--language", metavar="CODE",
        help="language hint (ISO 639-1, e.g. zh or en); omit to auto-detect "
        "(better for code-switching)",
    )
    parser.add_argument(
        "--context", metavar="TEXT",
        help="glossary/context prompt to bias names and jargon "
        "(whisper-1 accepts up to 224 tokens)",
    )
    parser.add_argument(
        "--pause", type=float, default=0.6, metavar="SECONDS",
        help="gap that starts a new segment (default 0.6)",
    )
    parser.add_argument(
        "--no-silence", action="store_true",
        help="skip ffmpeg silence detection (chunking and reporting)",
    )
    parser.add_argument(
        "--silence-db", type=silence_db, metavar="DB",
        help="silence threshold in dBFS, or auto (default): the audio's "
        f"measured noise floor + {FLOOR_MARGIN_DB:g} dB, "
        f"{SILENCE_FALLBACK_DB:g} dB if it has none",
    )
    parser.add_argument(
        "--estimate", action="store_true",
        help="print duration and estimated API cost as JSON, then exit "
        "(no key or API calls)",
    )
    parser.add_argument(
        "--from-json", action="store_true",
        help="re-render FILE, a --format json output, in --format with this "
        "--pause/--no-silence (no key, API calls, or ffmpeg)",
    )
    parser.add_argument(
        "--yes", action="store_true",
        help="skip the cost confirmation prompt on a TTY",
    )
    args = parser.parse_args(argv)
    if args.from_json and (
        args.estimate or args.language or args.context or args.silence_db
    ):
        parser.error(
            "--from-json makes no API call or ffmpeg run; --estimate, "
            "--language, --context and --silence-db do not apply"
        )
    if args.silence_db is None:
        args.silence_db = "auto"
    return args


def main(argv=None):
    args = parse_args(argv)
    try:
        if args.estimate:
            estimate(args)
            return EXIT_OK
        if args.from_json:
            result = rerender(load_transcript(args.file), args)
        else:
            api_key = os.environ.get("OPENAI_API_KEY")
            if not api_key:
                eprint(
                    "OPENAI_API_KEY is not set. Create/print one (needs the "
                    "Audio scope), then: export OPENAI_API_KEY=... "
                    "or run with `--estimate` first."
                )
                return EXIT_NOKEY
            if sys.stderr.isatty() and not args.yes:
                duration = probe(Path(args.file))
                cost = duration / 60 * PRICE_PER_MIN
                eprint(
                    f"about to transcribe {args.file} "
                    f"({duration:.0f}s, ~${cost:.2f}). Ctrl-C to abort."
                )
                time.sleep(1.5)
            result = process(args, make_client(api_key))
    except UsageError as err:
        eprint(err)
        return EXIT_USAGE
    except FileNotFoundError as err:
        eprint(f"missing tool (ffmpeg/ffprobe on PATH?): {err}")
        return EXIT_MEDIA
    except MediaError as err:
        eprint(err)
        return EXIT_MEDIA
    except ApiError as err:
        eprint(err)
        return EXIT_API

    rendered = render(result, args.format)
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
        eprint(f"wrote {args.output}")
    else:
        sys.stdout.write(rendered)
    if args.from_json:
        eprint(f"done: {len(result['segments'])} segment(s), no API call")
    else:
        eprint(
            f"done: {len(result['segments'])} segment(s), "
            f"~${result['estimated_cost_usd']:.2f}, "
            f"api {result['timings']['api_seconds']:.0f}s"
        )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
