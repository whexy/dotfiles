"""`strip`: filmstrip + waveform PNG of a time range, for drilling into a cut.

Ported from browser-use/video-use helpers/timeline_view.py
(https://github.com/browser-use/video-use), MIT License,
Copyright (c) 2026 Browser Use. Changes: reads transcribe's JSON schema,
shades detected silences instead of transcript gaps, can render the
assembled output around a cut (frames and audio mapped through the
plan), bins the waveform on exact time edges, and takes fonts from a Nix
store path.
"""

from pathlib import Path
import subprocess
import tempfile
import wave

import numpy as np
from PIL import Image, ImageDraw

from . import fonts, silence, transcript
from .common import MediaError, UsageError, find_root
from .media import run
from .timeline import kept_words

BG = (18, 18, 22)
FG = (235, 235, 235)
DIM = (110, 110, 120)
CUT = (248, 113, 113)
SILENCE = (50, 80, 120, 120)
WAVE = (140, 180, 255)
RATE = 16000


def extract_frame(video, t, out):
    run(
        [
            "ffmpeg", "-y", "-v", "error", "-ss", f"{max(t, 0):.3f}", "-i", str(video),
            "-frames:v", "1", "-q:v", "4", "-vf", "scale=320:-2", str(out),
        ]
    )


def pcm(video, start, end, wav=None):
    """Mono 16 kHz float samples of [start, end]; silence if no audio.

    `wav` is the source's cached 16 kHz audio: reading it keeps the
    waveform on the same clock as the silences detected from it, which an
    ffmpeg seek into compressed audio does not.
    """
    n = int(round((end - start) * RATE))
    if wav is not None:
        with wave.open(str(wav), "rb") as w:
            w.setpos(min(int(round(start * RATE)), w.getnframes()))
            data = np.frombuffer(w.readframes(n), dtype=np.int16)
        data = data.astype(np.float32) / 32768.0
        return np.pad(data, (0, max(0, n - data.size)))[:n]
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        result = subprocess.run(
            [
                "ffmpeg", "-y", "-v", "error", "-ss", f"{start:.3f}", "-i", str(video),
                "-t", f"{end - start:.3f}", "-vn", "-ac", "1", "-ar", str(RATE),
                "-c:a", "pcm_s16le", f.name,
            ],
            capture_output=True,
        )
        if result.returncode != 0:
            return np.zeros(n, dtype=np.float32)
        with wave.open(f.name, "rb") as w:
            data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    data = data.astype(np.float32) / 32768.0
    if data.size < n:
        data = np.pad(data, (0, n - data.size))
    return data[:n]


def envelope(samples, n):
    """RMS of `samples` in n equal bins, normalised to [0, 1].

    Bin edges are exact, so bin i covers time i/n of the strip; whole-sample
    windows would drift against the time axis across the strip.
    """
    if samples.size < n:
        samples = np.pad(samples, (0, n - samples.size))
    edges = np.linspace(0, samples.size, n + 1).astype(int)
    power = np.add.reduceat(samples.astype(np.float64) ** 2, edges[:-1])
    env = np.sqrt(power / np.maximum(np.diff(edges), 1))
    peak = env.max()
    return env / peak if peak > 0 else env


def render(pieces, words, silences, cuts, title, out, n_frames=10, wav=None):
    """Composite PNG.

    pieces: [(video, src_start, src_end, strip_start)] laid end to end;
    words/silences/cuts are in strip seconds; `wav` is the cached audio of
    the pieces' video, when there is one.
    """
    length = sum(b - a for _, a, b, _ in pieces)
    if length <= 0:
        raise UsageError("empty strip range")

    def source_at(t):
        for video, a, b, s in pieces:
            if s <= t <= s + (b - a) + 1e-9:
                return video, a + (t - s)
        video, a, b, s = pieces[-1]
        return video, b

    times = (
        [length / 2]
        if n_frames < 2
        else [i * length / (n_frames - 1) for i in range(n_frames)]
    )
    frame_h = 180
    strip_y, wave_y, wave_h = 50, 50 + frame_h + 34, 220
    canvas_h = wave_y + wave_h + 70
    with tempfile.TemporaryDirectory(prefix="video-edit-strip-") as tmp:
        imgs = []
        for i, t in enumerate(times):
            video, src_t = source_at(min(t, length - 1e-3))
            path = Path(tmp) / f"f_{i:03d}.jpg"
            extract_frame(video, src_t, path)
            img = Image.open(path).convert("RGB")
            imgs.append(img.resize((int(frame_h * img.width / img.height), frame_h)))
    total_w = sum(i.width for i in imgs) + 4 * (len(imgs) - 1)
    canvas_w = max(1920, min(total_w, 3000) + 100)
    strip_w = canvas_w - 100
    canvas = Image.new("RGB", (canvas_w, canvas_h), BG)
    draw = ImageDraw.Draw(canvas, "RGBA")
    header, label, small = fonts.load(22), fonts.load(14), fonts.load(16)
    draw.text((50, 12), title, fill=FG, font=header)

    scale = min(1.0, strip_w / total_w)
    x = 50
    for img in imgs:
        w, h = int(img.width * scale), int(frame_h * scale)
        canvas.paste(img.resize((w, h)), (x, strip_y + (frame_h - h) // 2))
        x += w + max(2, int(4 * scale))

    def tx(t):
        return int(50 + t / length * strip_w)

    draw.rectangle((50, wave_y, 50 + strip_w, wave_y + wave_h), fill=(28, 28, 34))
    for a, b in silences:
        draw.rectangle((tx(a), wave_y, tx(b), wave_y + wave_h), fill=SILENCE)
    samples = np.concatenate([pcm(v, a, b, wav) for v, a, b, _ in pieces])
    env = envelope(samples, strip_w)
    mid, amp = wave_y + wave_h // 2, wave_h // 2 - 8
    top = [(50 + i, mid - int(v * amp)) for i, v in enumerate(env)]
    bottom = [(50 + i, mid + int(v * amp)) for i, v in enumerate(env)]
    if top:
        draw.polygon(top + bottom[::-1], fill=(*WAVE, 70))
        draw.line(top, fill=WAVE, width=1)
        draw.line(bottom, fill=WAVE, width=1)
    for t in cuts:
        draw.line((tx(t), strip_y - 6, tx(t), wave_y + wave_h), fill=CUT, width=2)

    last_x = -9999
    for w in words:
        cx = (tx(w["start"]) + tx(w["end"])) // 2
        if cx - last_x < 18:
            continue
        draw.line((cx, wave_y - 4, cx, wave_y), fill=DIM, width=1)
        draw.text((cx - 6, wave_y - 26), w["word"], fill=FG, font=small)
        last_x = cx

    ruler_y = wave_y + wave_h + 2
    for i in range(7):
        t = i * length / 6
        xi = tx(t)
        draw.line((xi, ruler_y, xi, ruler_y + 6), fill=DIM, width=1)
        draw.text((xi - 20, ruler_y + 8), f"{t:.2f}s", fill=DIM, font=label)
    legend = "blue bands: detected silences"
    if cuts:
        legend += "; red lines: cuts"
    draw.text((50, ruler_y + 34), legend, fill=DIM, font=label)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG", optimize=True)
    return out


def _clip(spans, a, b, shift):
    return [(max(s, a) + shift, min(e, b) + shift) for s, e in spans if e > a and s < b]


def run_strip(video, start, end, output=None, n_frames=10, cut=None, around=2.0, version=None, root_arg=None):
    if cut is not None:
        return _cut_strip(cut, around, output, n_frames, version, root_arg)
    if video is None or start is None or end is None:
        raise UsageError("strip needs VIDEO START END, or --cut K")
    if end <= start:
        raise UsageError("end must be after start")
    video = Path(video).absolute()
    if not video.is_file():
        raise MediaError(f"not a file: {video}")
    root = None
    try:
        root = find_root(root_arg)
    except UsageError:
        pass
    words, spans, wav = [], [], None
    if root:
        path = root.transcript_path(video)
        if path.exists():
            _, all_words = transcript.load(path)
            words = [
                {**w, "start": w["start"] - start, "end": w["end"] - start}
                for w in all_words
                if w["end"] > start and w["start"] < end
            ]
        main = root.sources()["main"]
        if Path(main["path"]) == video:
            data = silence.load(root, main, root.spec())
            spans = _clip(data["silences"], start, end, -start)
            wav = silence.audio_cache(root, video)
    if output is None:
        base = root / "verify" if root else video.parent
        output = base / f"strip_{video.stem}_{start:.2f}-{end:.2f}.png"
    title = f"{video.name}   {start:.2f}s -> {end:.2f}s   ({end - start:.2f}s)"
    out = render(
        [(video, start, end, 0.0)], words, spans, [], title, Path(output), n_frames, wav
    )
    return 0, {"ok": True, "png": str(out)}


def _cut_strip(cut, around, output, n_frames, version, root_arg):
    from .context import Edit

    root = find_root(root_arg)
    plan = root.plan(version)
    ranges = plan["ranges"]
    if not 0 <= cut <= len(ranges):
        raise UsageError(f"cut {cut} not in 0-{len(ranges)} (cut k is the start of range k)")
    fps = plan["fps"]
    at = (ranges[cut]["rec_in"] if cut < len(ranges) else plan["duration_frames"]) / fps
    lo, hi = max(0.0, at - around), min(plan["duration_frames"] / fps, at + around)
    edit = Edit(root)
    main = Path(edit.main["path"])
    pieces, spans, cuts = [], [], []
    for r in ranges:
        r_in, r_out = r["rec_in"] / fps, r["rec_out"] / fps
        a, b = max(lo, r_in), min(hi, r_out)
        if b <= a:
            continue
        src_a = r["src_in"] / fps + (a - r_in)
        src_b = src_a + (b - a)
        pieces.append((main, src_a, src_b, a - lo))
        spans += _clip(edit.silences.spans, src_a, src_b, a - lo - src_a)
        if r_in > lo:
            cuts.append(r_in - lo)
    words = [
        {**w, "start": w["out_start"] - lo, "end": w["out_end"] - lo}
        for w in kept_words(ranges, edit.words, fps)
        if w["out_end"] > lo and w["out_start"] < hi
    ]
    if output is None:
        output = root / "verify" / f"strip_v{plan['version']}_cut{cut}.png"
    title = (
        f"v{plan['version']} cut {cut} at {at:.2f}s output   "
        f"{lo:.2f}s -> {hi:.2f}s (assembled)"
    )
    wav = silence.audio_cache(root, main)
    out = render(pieces, words, spans, cuts, title, Path(output), n_frames, wav)
    return 0, {"ok": True, "png": root.rel(out)}
