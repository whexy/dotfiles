#!/usr/bin/env python3
"""Transcribe an audio/video file into an agent-readable, word-timed transcript.

Two OpenAI models are used because no single one supplies both sides of
what a cutting decision needs: `gpt-transcribe` produces the most accurate
text (multi-language hints, keyword biasing) but returns no timestamps,
while `whisper-1` is the only model that returns word timestamps but a
generation behind on text. The accurate text is aligned onto the timed
words (proportional timing where the two disagree), then pauses, fillers
and repeated-word stumbles are annotated so an agent can propose cuts
from the transcript alone. Word timestamps are approximate (roughly
+/-0.1-0.5 s); treat them as decision support, not frame-accurate cut
points, until they are snapped to silence in the actual edit.

Default output is a compact annotated transcript; `--json` adds the full
word-level data. Exit codes: 0 ok, 2 usage, 3 media/ffmpeg, 4 API,
5 missing OPENAI_API_KEY.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from difflib import SequenceMatcher
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

API_URL = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
AUDIO_FORMATS = {"mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm"}
MAX_FILE = 24 * 1000 * 1000  # API limit is 25 MB; leave multipart headroom
CHUNK_SECONDS = 600.0
SILENCE_NOISE = "-40dB"
SILENCE_MIN = 0.3

EXIT_OK, EXIT_USAGE, EXIT_MEDIA, EXIT_API, EXIT_NOKEY = 0, 2, 3, 4, 5

PRICES_PER_MIN = {"gpt-transcribe": 0.0045, "whisper-1": 0.006}

FILLERS_EN = {
    "um", "uh", "uhm", "umm", "uhh", "er", "erm", "hmm", "mm", "mhm",
    "ah", "eh", "like", "basically", "actually", "literally",
}
FILLERS_ZH = {"嗯", "呃", "啊", "那个", "就是", "然后"}


class MediaError(Exception):
    pass


class ApiError(Exception):
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


def detect_silences(path):
    """Sorted [(start, end), ...] silence intervals from ffmpeg silencedetect."""
    result = subprocess.run(
        [
            "ffmpeg", "-v", "info", "-i", str(path),
            "-af", f"silencedetect=noise={SILENCE_NOISE}:d={SILENCE_MIN}",
            "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    log = result.stderr
    starts = [float(m) for m in re.findall(r"silence_start: ([\d.]+)", log)]
    ends = [float(m) for m in re.findall(r"silence_end: ([\d.]+)", log)]
    return sorted(zip(starts, ends))


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
    data = path.read_bytes()
    accurate, timed, next_prompt = None, None, None
    if not args.timing_only:
        fields = [("model", "gpt-transcribe")]
        if args.context:
            fields.append(("prompt", args.context))
        for language in args.languages or []:
            fields.append(("languages[]", language))
        for keyword in args.keywords or []:
            fields.append(("keywords[]", keyword))
        accurate = client(fields, path.name, data)
        next_prompt = accurate.get("text", "")[-200:] or None
    fields = [
        ("model", "whisper-1"),
        ("response_format", "verbose_json"),
        ("timestamp_granularities[]", "word"),
        ("timestamp_granularities[]", "segment"),
    ]
    if args.whisper_language:
        fields.append(("language", args.whisper_language))
    timed = client(fields, path.name, data)
    return accurate, timed, next_prompt


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


def align_words(ref_text, timed_words, span):
    """Time `ref_text` tokens using `timed_words` [(text, start, end), ...].

    Tokens matched by sequence alignment inherit the matched span; runs of
    unmatched reference tokens split the time between neighbouring matches
    in proportion to character length. Alignment runs on normalised keys
    so punctuation/casing differences between the two models still match;
    tokens that normalise to nothing (bare punctuation) always take the
    interpolated path.
    """
    ref = ref_text.split()
    if not ref:
        return []
    if not timed_words:
        step = (span[1] - span[0]) / len(ref)
        return [
            (w, span[0] + i * step, span[0] + (i + 1) * step, False)
            for i, w in enumerate(ref)
        ]
    ref_keys = [norm_key(w) for w in ref]
    timed_keys = [norm_key(w) for w, _, _ in timed_words]
    times = {}
    matcher = SequenceMatcher(a=ref_keys, b=timed_keys, autojunk=False)
    for a_lo, b_lo, size in matcher.get_matching_blocks():
        for k in range(size):
            if not ref_keys[a_lo + k]:
                continue
            _, start, end = timed_words[b_lo + k]
            times[a_lo + k] = (start, end)
    return [
        (w, times[i][0], times[i][1], True)
        if i in times
        else (w, *_interpolated(ref, times, i, timed_words, span), False)
        for i, w in enumerate(ref)
    ]


def _interpolated(ref, times, i, timed_words, span):
    before = max((j for j in times if j < i), default=None)
    after = min((j for j in times if j > i), default=None)
    lo = times[before][1] if before is not None else span[0]
    hi = times[after][0] if after is not None else span[1]
    lo = max(lo, span[0])
    hi = max(hi, lo)
    run_start = before + 1 if before is not None else 0
    run_end = after - 1 if after is not None else len(ref) - 1
    weights = [max(1, len(ref[j])) for j in range(run_start, run_end + 1)]
    total = sum(weights)
    pos = i - run_start
    start = lo + (hi - lo) * sum(weights[:pos]) / total
    end = lo + (hi - lo) * sum(weights[: pos + 1]) / total
    return start, end


def annotate(words):
    """Attach gap_after/filler/stumble to each word dict, in place."""
    for i, word in enumerate(words):
        word["gap_after"] = (
            round(words[i + 1]["start"] - word["end"], 3)
            if i + 1 < len(words)
            else None
        )
        word["filler"] = is_filler(word["word"])
        word["stumble"] = False
    for i in range(1, len(words)):
        prev, cur = norm_key(words[i - 1]["word"]), norm_key(words[i]["word"])
        if (
            prev
            and prev == cur
            and words[i]["start"] - words[i - 1]["end"] < 1.5
        ):
            words[i - 1]["stumble"] = True
            words[i]["stumble"] = True
    return words


def is_filler(word):
    key = norm_key(word)
    return key in FILLERS_EN or word in FILLERS_ZH or key in FILLERS_ZH


def collapse_silences(silences, words):
    """Silences not already implied by a word gap (music, dead air)."""
    gaps = [
        (words[i]["end"], words[i + 1]["start"])
        for i in range(len(words) - 1)
        if words[i + 1]["start"] > words[i]["end"]
    ]
    return [
        (s, e)
        for s, e in silences
        if not any(s >= gs - 0.05 and e <= ge + 0.05 for gs, ge in gaps)
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
        f"models={','.join(result['models'])} duration={result['duration']:.1f}s",
        "# [MM:SS.ss-MM:SS.ss] segments split on pauses; "
        "(pause Xs) = silence before segment",
        "# {word} = filler, {{word}} = stumble (repeated word), "
        "<pause 1.2s> inline = long pause inside a segment",
        "# word timings +/-0.1-0.5s: snap cut points to silence "
        "and add handles before cutting",
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
            chunks = [(0.0, duration)]
            files = [source]
            silences = [] if args.no_silence else detect_silences(source)
        else:
            audio = workdir / "audio.mp3"
            extract_audio(source, audio)
            silences = [] if args.no_silence else detect_silences(audio)
            chunks = plan_chunks(duration, silences)
            eprint(
                f"duration {duration:.0f}s, {len(chunks)} chunk(s); silences "
                "not implied by speech gaps are reported in the output"
            )
            files = (
                [audio] if len(chunks) == 1 else split_audio(audio, chunks, workdir)
            )
        timings["media_seconds"] = round(time.monotonic() - started, 2)

        started = time.monotonic()
        if args.timing_only or len(files) == 1:
            results = [transcribe_chunk(client, files[0], args)]
            context = args.context
            for extra in files[1:]:
                carry = argparse.Namespace(**vars(args))
                carry.context = results[-1][2] or context
                results.append(transcribe_chunk(client, extra, carry))
        else:
            # Context carry-over needs sequential results; parallel chunks
            # each get the user-supplied context instead.
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(
                    pool.map(lambda f: transcribe_chunk(client, f, args), files)
                )
        timings["api_seconds"] = round(time.monotonic() - started, 2)

    words, languages = [], []
    for (offset, chunk_end), (accurate, timed, _) in zip(chunks, results):
        timed_words = [
            (w.get("word", ""), offset + w["start"], offset + w["end"])
            for w in timed.get("words", [])
        ]
        if args.timing_only:
            aligned = [(w, s, e, True) for w, s, e in timed_words]
        else:
            for lang in accurate.get("languages", []):
                code = lang.get("code") if isinstance(lang, dict) else lang
                if code and code not in languages:
                    languages.append(code)
            aligned = align_words(
                accurate.get("text", ""), timed_words, (offset, chunk_end)
            )
        words += [
            {
                "word": w,
                "start": round(s, 3),
                "end": round(e, 3),
                "source": "timed" if ok else "interpolated",
            }
            for w, s, e, ok in aligned
            if w
        ]
    if not languages and results:
        code = results[0][1].get("language")
        if code:
            languages = [code]

    words.sort(key=lambda w: w["start"])
    annotate(words)
    segments = group_segments(words, args.pause)
    models = ["whisper-1"] if args.timing_only else ["gpt-transcribe", "whisper-1"]
    billed = duration / 60 * sum(PRICES_PER_MIN[m] for m in models)
    return {
        "source": str(source),
        "duration": duration,
        "models": models,
        "languages": languages,
        "estimated_cost_usd": round(billed, 4),
        "timings": timings,
        "segments": segments,
        "silences": collapse_silences(silences, words),
    }


def estimate(args):
    duration = probe(Path(args.file))
    models = ["whisper-1"] if args.timing_only else ["gpt-transcribe", "whisper-1"]
    per_model = {
        m: round(duration / 60 * PRICES_PER_MIN[m], 4) for m in models
    }
    print(
        json.dumps(
            {
                "source": args.file,
                "duration_seconds": round(duration, 1),
                "models": models,
                "estimated_cost_usd": per_model,
                "estimated_total_usd": round(sum(per_model.values()), 4),
            },
            indent=2,
        )
    )


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        epilog="stdout carries only the transcript; progress goes to stderr. "
        "Exit codes: 0 ok, 2 usage, 3 media/ffmpeg, 4 API, 5 missing key.",
    )
    parser.add_argument("file", help="audio or video file to transcribe")
    parser.add_argument(
        "-o", "--output", help="write to this file instead of stdout"
    )
    parser.add_argument(
        "--format", choices=["text", "json", "srt"], default="text",
        help="default text; json includes every word with start/end/gap "
        "and filler/stumble flags",
    )
    parser.add_argument(
        "--languages", nargs="+", metavar="CODE",
        help="language hints for the accurate pass, e.g. --languages zh-cn en",
    )
    parser.add_argument(
        "--whisper-language", metavar="CODE",
        help="single-language hint for the timing pass; omit to auto-detect "
        "(better for code-switching)",
    )
    parser.add_argument(
        "--keywords", nargs="+", metavar="TERM",
        help="names/jargon to bias the accurate pass towards",
    )
    parser.add_argument(
        "--context", help="recording context prompt for the accurate pass"
    )
    parser.add_argument(
        "--pause", type=float, default=0.6, metavar="SECONDS",
        help="gap that starts a new segment (default 0.6)",
    )
    parser.add_argument(
        "--timing-only", action="store_true",
        help="skip gpt-transcribe; whisper-1 words and timing only",
    )
    parser.add_argument(
        "--no-silence", action="store_true",
        help="skip ffmpeg silence detection (chunking and reporting)",
    )
    parser.add_argument(
        "--estimate", action="store_true",
        help="print duration and estimated API cost as JSON, then exit "
        "(no key or API calls)",
    )
    parser.add_argument(
        "--yes", action="store_true",
        help="skip the cost confirmation prompt on a TTY",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        if args.estimate:
            estimate(args)
            return EXIT_OK
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
            models = (
                ["whisper-1"] if args.timing_only
                else ["gpt-transcribe", "whisper-1"]
            )
            cost = duration / 60 * sum(PRICES_PER_MIN[m] for m in models)
            eprint(
                f"about to transcribe {args.file} "
                f"({duration:.0f}s, ~${cost:.2f}). Ctrl-C to abort."
            )
            time.sleep(1.5)
        result = process(args, make_client(api_key))
    except FileNotFoundError as err:
        eprint(f"missing tool (ffmpeg/ffprobe on PATH?): {err}")
        return EXIT_MEDIA
    except MediaError as err:
        eprint(err)
        return EXIT_MEDIA
    except ApiError as err:
        eprint(err)
        return EXIT_API

    if args.format == "json":
        rendered = json.dumps(result, ensure_ascii=False, indent=2)
    elif args.format == "srt":
        rendered = render_srt(result["segments"])
    else:
        rendered = render_text(result)
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
        eprint(f"wrote {args.output}")
    else:
        sys.stdout.write(rendered)
    eprint(
        f"done: {len(result['segments'])} segment(s), "
        f"~${result['estimated_cost_usd']:.2f}, "
        f"api {result['timings']['api_seconds']:.0f}s"
    )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
