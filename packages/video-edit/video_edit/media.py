"""ffprobe/ffmpeg wrappers."""

from fractions import Fraction
import json
import math
from pathlib import Path
import subprocess

from .common import MediaError

ALPHA_FORMATS = ("yuva", "rgba", "bgra", "argb", "abgr", "gbrap", "ya8", "ya16")
RGB_FORMATS = ("rgb", "bgr", "gbr", "argb", "abgr", "rgba", "bgra", "0rgb", "rgb0")


def run(cmd, **kwargs):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    except FileNotFoundError as err:
        raise MediaError(f"{cmd[0]} not found on PATH") from err
    if result.returncode != 0:
        tail = " ".join(result.stderr.strip().splitlines()[-6:])
        raise MediaError(f"{cmd[0]} failed: {tail}")
    return result


def ffprobe(path, *args):
    if not Path(path).is_file():
        raise MediaError(f"not a file: {path}")
    out = run(["ffprobe", "-v", "error", *args, "-of", "json", str(path)]).stdout
    return json.loads(out or "{}")


def rate(text):
    """'60/1' -> Fraction(60); '0/0' or junk -> None."""
    try:
        value = Fraction(str(text))
    except (ValueError, ZeroDivisionError):
        return None
    return value if value > 0 else None


def fps_value(fraction):
    """An int when the rate is whole, else a float."""
    if fraction.denominator == 1:
        return int(fraction)
    return float(fraction)


def _clock(text):
    """'00:59:12.316667000' -> seconds, or None."""
    try:
        h, m, s = str(text).split(":")
        return int(h) * 3600 + int(m) * 60 + float(s)
    except ValueError:
        return None


def frames_of(seconds, fps):
    """Nearest frame, rounding halves up (never banker's rounding)."""
    return int(math.floor(seconds * fps + 0.5 + 1e-9))


def probe_source(path):
    """Fields sources.json records for a recording."""
    info = ffprobe(
        path,
        "-show_entries",
        "stream=index,codec_type,codec_name,width,height,r_frame_rate,"
        "avg_frame_rate,nb_frames,duration:stream_tags=timecode,DURATION"
        ":format=duration:format_tags=timecode",
    )
    streams = info.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    if video is None:
        raise MediaError(f"no video stream in {path}")
    fps = rate(video.get("r_frame_rate"))
    avg = rate(video.get("avg_frame_rate"))
    if fps is None:
        raise MediaError(f"cannot read the frame rate of {path}")
    tags = video.get("tags") or {}
    # Matroska has no nb_frames, and its container duration includes audio
    # priming; the video stream's own DURATION tag is exact.
    duration = (
        video.get("duration")
        or _clock(tags.get("DURATION"))
        or info.get("format", {}).get("duration")
    )
    if duration is None:
        raise MediaError(f"cannot determine the duration of {path}")
    duration = float(duration)
    nb_frames = video.get("nb_frames")
    frames = int(nb_frames) if nb_frames else frames_of(duration, fps)
    timecode = tags.get("timecode") or (info.get("format", {}).get("tags") or {}).get(
        "timecode"
    )
    return {
        "path": str(Path(path).absolute()),
        "file_name": Path(path).name,
        "fps": fps_value(fps),
        "fps_rational": f"{fps.numerator}/{fps.denominator}",
        "vfr": avg is not None and avg != fps,
        "frames": frames,
        "frames_from": "nb_frames" if nb_frames else "duration",
        "duration": round(duration, 6),
        "width": video.get("width"),
        "height": video.get("height"),
        "video_codec": video.get("codec_name"),
        "has_audio": any(s.get("codec_type") == "audio" for s in streams),
        "start_timecode": timecode or "00:00:00:00",
    }


def probe_video(path, count="frames"):
    """First video stream facts for check/finalize.

    count: "frames" decodes every frame (exact, slower), "packets" only
    demuxes, None skips counting.
    """
    args = ["-select_streams", "v:0"]
    if count == "frames":
        args.append("-count_frames")
    elif count == "packets":
        args.append("-count_packets")
    info = ffprobe(
        path,
        *args,
        "-show_entries",
        "stream=codec_name,profile,pix_fmt,width,height,r_frame_rate,"
        "avg_frame_rate,nb_frames,nb_read_frames,nb_read_packets,duration,"
        "color_space,color_range,color_primaries,color_transfer"
        ":stream_tags=encoder,alpha_mode:format=duration",
    )
    streams = info.get("streams") or []
    if not streams:
        raise MediaError(f"no video stream in {path}")
    s = streams[0]
    tags = s.get("tags") or {}
    pix_fmt = s.get("pix_fmt") or ""
    counted = s.get("nb_read_frames") or s.get("nb_read_packets")
    duration = s.get("duration") or info.get("format", {}).get("duration")
    return {
        "codec": s.get("codec_name"),
        "profile": s.get("profile"),
        "pix_fmt": pix_fmt,
        "width": s.get("width"),
        "height": s.get("height"),
        "r_frame_rate": s.get("r_frame_rate"),
        "avg_frame_rate": s.get("avg_frame_rate"),
        "frames": int(counted) if counted else None,
        "nb_frames": int(s["nb_frames"]) if s.get("nb_frames") else None,
        "duration": float(duration) if duration else None,
        "color_space": s.get("color_space"),
        "color_range": s.get("color_range"),
        "color_primaries": s.get("color_primaries"),
        "color_transfer": s.get("color_transfer"),
        "encoder": tags.get("encoder"),
        "alpha": pix_fmt.startswith(ALPHA_FORMATS) or tags.get("alpha_mode") == "1",
        "rgb": pix_fmt.startswith(RGB_FORMATS),
    }


def sniff_encoder(path, limit=8 * 1024 * 1024):
    """Encoder library named in the stream's SEI/headers, if any."""
    with open(path, "rb") as fh:
        head = fh.read(limit)
    for marker, name in (
        (b"x264 - core", "libx264"),
        (b"x265 (build", "libx265"),
        (b"hevc_nvenc", "hevc_nvenc"),
        (b"h264_nvenc", "h264_nvenc"),
        (b"av1_nvenc", "av1_nvenc"),
        (b"hevc_videotoolbox", "hevc_videotoolbox"),
        (b"h264_videotoolbox", "h264_videotoolbox"),
    ):
        if marker in head:
            return name
    return None
