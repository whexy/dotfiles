"""`finalize` (NVENC encode to the slot spec) and `check` (verify a render)."""

from fractions import Fraction
import os
from pathlib import Path
import re
import tempfile

from .common import MediaError, UsageError, write_json
from .media import frames_of, probe_video, rate, run, sniff_encoder
from .slots import check_record, load_slot, outputs

# Pixel formats the `colorspace` filter accepts; other YUV input goes
# through `scale`, which converts matrices slightly less accurately.
COLORSPACE_FORMATS = {
    f"yuv{s}p{d}" for s in ("420", "422", "444") for d in ("", "10le", "12le")
}
MATRIX_TAGS = {"bt709": "bt709", "bt470bg": "bt601", "smpte170m": "bt601"}
UNTAGGED = {None, "", "unknown", "unspecified", "reserved"}
COLORSPACE_NAME = {"bt709": "bt709", "bt601": "bt470bg"}
OUT_TAGS = "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv"
SCALE_FLAGS = "flags=lanczos+accurate_rnd+full_chroma_int"
MANIMGX = "manimgx"


def raw_timing(info):
    """A raw render's frame rate and the number of frames in its clip.

    ManimGX stores a picture held still as one sample lasting several frames,
    so its packets undercount and its average rate drifts; its duration on
    its stream rate counts the frames instead. It also closes on a frame at
    the scene's own end, one past the clip.
    """
    if info["encoder"] != MANIMGX:
        return rate(info["avg_frame_rate"]) or rate(info["r_frame_rate"]), info["frames"]
    fps = rate(info["r_frame_rate"])
    if fps is None or not info["duration"]:
        return fps, None
    return fps, frames_of(info["duration"], fps) - 1


def colour_input(info, matrix="auto", rng="auto"):
    """How to read a raw render's colours.

    An untagged matrix is read as BT.601, which ffmpeg and libx264 use to
    convert RGB to YUV unless told otherwise. ManimGX tags BT.601 (smpte170m)
    and HyperFrames tags only the matrix (bt709); both tags are honoured.
    """
    if info["rgb"]:
        return {"kind": "rgb", "matrix": None, "range": "pc", "notes": ["RGB input"]}
    notes = []
    if matrix == "auto":
        tag = info["color_space"]
        if tag in MATRIX_TAGS:
            matrix = MATRIX_TAGS[tag]
            notes.append(f"matrix from tag {tag}")
        elif tag in UNTAGGED:
            matrix = "bt601"
            notes.append(
                "matrix untagged: read as BT.601 (ffmpeg's RGB->YUV default, "
                "e.g. libx264); pass --input-matrix bt709 if the renderer "
                "converted with BT.709"
            )
        else:
            raise MediaError(
                f"input matrix {tag} is not supported; pass --input-matrix bt601|bt709"
            )
    else:
        notes.append(f"matrix forced to {matrix}")
    if rng == "auto":
        tag = info["color_range"]
        if tag in ("tv", "pc"):
            rng = tag
        elif info["pix_fmt"].startswith("yuvj"):
            rng = "pc"
        else:
            rng = "tv"
            notes.append("range untagged: read as limited (tv)")
    else:
        notes.append(f"range forced to {rng}")
    kind = "yuv" if info["pix_fmt"] in COLORSPACE_FORMATS else "yuv-scale"
    return {"kind": kind, "matrix": matrix, "range": rng, "notes": notes}


def filter_graph(colour, info, width, height, fps, raw_fps, pad):
    """-vf for a raw render: BT.709 limited 4:2:0 at the slot size and rate."""
    resize = (info["width"], info["height"]) != (width, height)
    parts = []
    if colour["kind"] == "yuv":
        parts.append(
            "colorspace="
            f"ispace={COLORSPACE_NAME[colour['matrix']]}:irange={colour['range']}"
            ":iprimaries=bt709:itrc=bt709:space=bt709:range=tv:primaries=bt709"
            ":trc=bt709:format=yuv420p:fast=1"
        )
        if resize:
            parts.append(
                f"scale={width}:{height}:in_color_matrix=bt709:in_range=tv"
                f":out_color_matrix=bt709:out_range=tv:{SCALE_FLAGS}"
            )
    elif colour["kind"] == "yuv-scale":
        parts.append(
            f"scale={width}:{height}:in_color_matrix={colour['matrix']}"
            f":in_range={colour['range']}:out_color_matrix=bt709:out_range=tv"
            f":{SCALE_FLAGS}"
        )
    else:
        parts.append(
            f"scale={width}:{height}:out_color_matrix=bt709:out_range=tv:{SCALE_FLAGS}"
        )
    parts.append("format=yuv420p")
    if raw_fps != fps:
        parts.append(f"fps={fps}")
    if pad > 0:
        parts.append(f"tpad=stop_mode=clone:stop={pad}")
    parts.append(OUT_TAGS)
    return ",".join(parts)


def encode_args(spec, fps, frames, encoder):
    if encoder.endswith("_nvenc"):
        nv = spec["final"]["nvenc"]
        codec = [
            "-c:v", encoder, "-preset", nv["preset"], "-tune", nv["tune"],
            "-rc", "vbr", "-cq", str(nv["cq"]), "-b:v", "0",
            "-maxrate", nv["maxrate"], "-bufsize", nv["bufsize"],
            "-profile:v", spec["final"]["profile"], "-g", str(fps), "-bf", "2",
        ]
    else:
        codec = ["-c:v", encoder]
        if encoder == "libx265":
            codec += ["-preset", "ultrafast", "-x265-params", "log-level=error"]
    tag = ["-tag:v", "hvc1"] if "265" in encoder or "hevc" in encoder else []
    return codec + [
        "-fps_mode", "cfr", "-r", str(fps), "-frames:v", str(frames),
        "-color_primaries", "bt709", "-color_trc", "bt709",
        "-colorspace", "bt709", "-color_range", "tv",
        *tag, "-movflags", "+faststart", "-an",
    ]


def next_output(slot_dir, slot_id):
    found = outputs(slot_dir, slot_id)
    n = found[-1][0] + 1 if found else 1
    return Path(slot_dir) / "out" / f"{slot_id}_v{n}.mp4"


def run_finalize(root, raw, slot_arg, matrix="auto", rng="auto", dry_run=False):
    slot, slot_dir = load_slot(slot_arg)
    if slot.get("alpha"):
        raise UsageError("alpha slots can't be finalized: the final spec is 4:2:0 HEVC")
    spec = root.spec()
    info = probe_video(raw, count="packets")
    if info["alpha"]:
        raise MediaError(
            f"{raw} has an alpha channel; slots are full-screen and opaque, so "
            "render on the style background"
        )
    raw_fps, raw_frames = raw_timing(info)
    if raw_fps is None or not raw_frames:
        raise MediaError(f"cannot read the frame rate or frame count of {raw}")
    fps = slot["fps"]
    converted = frames_of(raw_frames / raw_fps, fps)
    shortfall = slot["frames"] - converted
    if abs(shortfall) > 1:
        need = frames_of(slot["frames"] / fps, raw_fps)
        return 1, {
            "ok": False,
            "errors": [
                f"raw has {raw_frames} frames at {float(raw_fps):g} fps "
                f"({converted} at {fps}); the slot needs exactly {slot['frames']}: "
                f"render {need} frames at {float(raw_fps):g} fps"
            ],
        }
    colour = colour_input(info, matrix, rng)
    vf = filter_graph(
        colour, info, slot["width"], slot["height"], fps, raw_fps, max(0, shortfall)
    )
    encoder = os.environ.get("VIDEO_EDIT_ENCODER") or spec["final"]["encoder"]
    out = next_output(slot_dir, slot["id"])
    partial = out.with_name(f".{out.stem}.partial.mp4")
    cmd = [
        "ffmpeg", "-hide_banner", "-v", "error", "-y", "-i", str(raw), "-vf", vf,
        *encode_args(spec, fps, slot["frames"], encoder), str(partial),
    ]
    notes = list(colour["notes"])
    if raw_fps != fps:
        notes.append(f"frame rate converted {float(raw_fps):g} -> {fps}")
    if shortfall > 0:
        notes.append(f"last frame held for {shortfall} frame(s)")
    elif shortfall < 0:
        notes.append(f"trimmed {-shortfall} frame(s)")
    payload = {
        "ok": True,
        "out": root.rel(out),
        "frames": slot["frames"],
        "input": {
            "frames": raw_frames,
            "fps": f"{raw_fps.numerator}/{raw_fps.denominator}",
            "pix_fmt": info["pix_fmt"],
            "matrix": colour["matrix"],
            "range": colour["range"],
        },
        "encoder": encoder,
        "notes": notes,
    }
    if dry_run:
        return 0, {**payload, "dry_run": True, "command": cmd}
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        run(cmd)
        partial.replace(out)
    finally:
        partial.unlink(missing_ok=True)
    payload["next"] = f"video-edit check {root.rel(out)} --slot {root.rel(slot_dir)}"
    return 0, payload


TEXT_SUFFIXES = {
    ".html", ".htm", ".svg", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx",
    ".vue", ".py", ".css",
}
CJK = re.compile("[぀-ヿ㐀-䶿一-鿿豈-﫿가-힯]")
BLOCKS = re.compile(r"<script\b.*?</script>|<style\b.*?</style>|<!--.*?-->", re.S | re.I)
TEXT_PATTERNS = (
    # DOM text nodes (also SVG <text>)
    (re.compile(r">([^<>]+)<"), {".html", ".htm", ".svg", ".vue", ".jsx", ".tsx"}),
    (
        re.compile(
            r"(?:textContent|innerText|innerHTML|outerHTML)\s*[+]?=\s*([`'\"])(.*?)\1"
            r"|(?:fillText|strokeText|createTextNode)\(\s*([`'\"])(.*?)\3",
            re.S,
        ),
        None,
    ),
    (
        re.compile(
            r"\b(?:Text|MarkupText|Tex|MathTex|Paragraph|Title|BulletedList)"
            r"\(\s*[rfbu]{0,2}([`'\"])(.*?)\1"
        ),
        {".py"},
    ),
    (re.compile(r"\bcontent\s*:\s*(['\"])(.+?)\1"), {".css", ".html", ".htm", ".vue"}),
)


def _visible(text, whitelist):
    text = re.sub(r"&[a-z]+;|&#\d+;", " ", text)
    for word in whitelist:
        text = re.sub(re.escape(word), " ", text, flags=re.I)
    return re.search(r"\w", text) is not None


def text_findings(src_dir, whitelist, limit=20):
    """Heuristic: CJK characters and visible text in a slot's sources."""
    findings = []
    src_dir = Path(src_dir)
    if not src_dir.is_dir():
        return findings
    for path in sorted(src_dir.rglob("*")):
        if (
            not path.is_file()
            or path.suffix.lower() not in TEXT_SUFFIXES
            or "node_modules" in path.parts
        ):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        rel = path.relative_to(src_dir.parent)
        for n, line in enumerate(text.splitlines(), 1):
            if CJK.search(line):
                findings.append(f"{rel}:{n}: CJK characters: {line.strip()[:60]}")
        blanked = BLOCKS.sub(lambda m: "\n" * m.group(0).count("\n"), text)
        for pattern, suffixes in TEXT_PATTERNS:
            if suffixes and path.suffix.lower() not in suffixes:
                continue
            source = blanked if pattern is TEXT_PATTERNS[0][0] else text
            for m in pattern.finditer(source):
                value = next((g for g in reversed(m.groups()) if g), "")
                if value.strip() and _visible(value, whitelist):
                    line = source.count("\n", 0, m.start()) + 1
                    findings.append(f"{rel}:{line}: visible text {value.strip()[:60]!r}")
    unique = list(dict.fromkeys(findings))
    if len(unique) > limit:
        unique = unique[:limit] + [f"... and {len(unique) - limit} more"]
    return unique


def contact_sheet(path, total, fps, out, count=12, cols=4, tile_w=480):
    """N evenly spaced frames at `fps` tiled into one PNG, alpha on a checkerboard.

    `fps` resamples first, so a held picture counts every frame it shows.
    """
    from PIL import Image, ImageDraw

    from . import fonts

    total = max(1, total or 1)
    picks = sorted({round(i * (total - 1) / max(1, count - 1)) for i in range(count)})
    expr = "+".join(f"eq(n,{p})" for p in picks)
    with tempfile.TemporaryDirectory(prefix="video-edit-sheet-") as tmp:
        run(
            [
                "ffmpeg", "-v", "error", "-i", str(path), "-vf",
                f"fps={fps},select='{expr}',scale={tile_w}:-2,format=rgba",
                "-fps_mode", "passthrough", "-frames:v", str(len(picks)),
                f"{tmp}/f_%03d.png",
            ]
        )
        frames = [Image.open(p).convert("RGBA") for p in sorted(Path(tmp).glob("f_*.png"))]
    if not frames:
        raise MediaError(f"no frames decoded from {path}")
    tile_h = frames[0].height
    label_h = 28
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile_w, rows * (tile_h + label_h)), (18, 18, 22))
    draw = ImageDraw.Draw(sheet)
    font = fonts.load(16)
    check = Image.new("RGBA", (tile_w, tile_h), (58, 58, 64, 255))
    checker = ImageDraw.Draw(check)
    for y in range(0, tile_h, 16):
        for x in range(0, tile_w, 16):
            if (x // 16 + y // 16) % 2:
                checker.rectangle((x, y, x + 15, y + 15), fill=(38, 38, 44, 255))
    for k, (frame, pick) in enumerate(zip(frames, picks)):
        x, y = (k % cols) * tile_w, (k // cols) * (tile_h + label_h)
        tile = Image.alpha_composite(check, frame.resize((tile_w, tile_h)))
        sheet.paste(tile.convert("RGB"), (x, y))
        draw.text(
            (x + 6, y + tile_h + 5),
            f"frame {pick}  {pick / fps:.2f}s",
            fill=(220, 220, 225),
            font=font,
        )
    sheet.save(out, "PNG", optimize=True)
    return out


def run_check(root, file, slot_arg, draft=False):
    slot, slot_dir = load_slot(slot_arg)
    spec = root.spec()
    file = Path(file)
    info = probe_video(file, count="frames")
    problems = []
    want = slot["draft"] if draft else slot
    if (info["width"], info["height"]) != (want["width"], want["height"]):
        problems.append(
            f"size {info['width']}x{info['height']}, want {want['width']}x{want['height']}"
        )
    _, frames = raw_timing(info)
    rates = ["r_frame_rate"]
    if info["encoder"] != MANIMGX:
        rates.append("avg_frame_rate")
    for key in rates:
        if rate(info[key]) != Fraction(want["fps"]):
            problems.append(f"{key} {info[key]}, want {want['fps']}")
    if frames != want["frames"]:
        problems.append(f"{frames} frames, want {want['frames']}")
    if info["alpha"] and not slot.get("alpha"):
        problems.append(f"has alpha ({info['pix_fmt']}); the slot is opaque")
    if not draft:
        final = spec["final"]
        if info["codec"] != final["codec"]:
            problems.append(f"codec {info['codec']}, want {final['codec']}")
        tag = info["encoder"] or ""
        sniffed = sniff_encoder(file) or ""
        cpu = [e for e in ("libx264", "libx265") if e in tag or e == sniffed]
        if cpu:
            problems.append(
                f"encoded with {cpu[0]} on the CPU, not NVENC; run `video-edit finalize`"
            )
        elif "nvenc" not in tag and "nvenc" not in sniffed:
            problems.append(f"cannot confirm an NVENC encoder (tag {tag or 'none'})")
        if info["pix_fmt"] != final["pix_fmt"]:
            problems.append(f"pix_fmt {info['pix_fmt']}, want {final['pix_fmt']}")
        colour = final["color"]
        for key, want_tag in (
            ("color_primaries", colour["primaries"]),
            ("color_transfer", colour["transfer"]),
            ("color_space", colour["matrix"]),
            ("color_range", colour["range"]),
        ):
            if info[key] != want_tag:
                problems.append(f"{key} {info[key] or 'untagged'}, want {want_tag}")
    rules = spec.get("rules", {})
    if not rules.get("text", False):
        problems += text_findings(slot_dir / "src", rules.get("textWhitelist", []))
    sheet = file.with_suffix(".sheet.png")
    try:
        contact_sheet(file, frames, want["fps"], sheet)
    except MediaError as err:
        problems.append(f"contact sheet failed: {err}")
        sheet = None
    stat = file.stat()
    record = {
        "pass": not problems,
        "mode": "draft" if draft else "final",
        "slot": slot["id"],
        "signature": slot["signature"],
        "problems": problems,
        "frames": frames,
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }
    write_json(check_record(file), record)
    return (0 if not problems else 1), {
        "pass": not problems,
        "file": root.rel(file),
        "mode": record["mode"],
        "problems": problems,
        "sheet": root.rel(sheet) if sheet else None,
        "probe": {
            k: info[k]
            for k in (
                "codec", "encoder", "pix_fmt", "width", "height", "r_frame_rate",
                "avg_frame_rate", "frames", "color_primaries", "color_transfer",
                "color_space", "color_range",
            )
        },
    }
