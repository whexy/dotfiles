"""Command line: one subcommand per step; JSON on stdout, progress on stderr."""

import argparse
import json
from pathlib import Path
import sys

from .common import EXIT_FAIL, Root, ToolError, UsageError, eprint, find_root, read_json

EPILOG = (
    "Run commands inside an edit root (or pass --root). stdout carries one "
    "JSON result (words: text); progress goes to stderr. Exit codes: 0 ok, "
    "1 checked and found problems, 2 usage, 3 media/ffmpeg, 4 transcribe "
    "failed, 5 OPENAI_API_KEY missing."
)


def parser():
    top = argparse.ArgumentParser(
        prog="video-edit",
        description="Deterministic core for cutting a recording into a DaVinci "
        "Resolve timeline: frame math, Resolve scripts, B-roll slots, checks.",
        epilog=EPILOG,
    )
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument("--root", metavar="DIR", help="edit root (default: found from the cwd)")
    sub = top.add_subparsers(dest="command", required=True, metavar="COMMAND")

    def cmd(name, help_text):
        return sub.add_parser(name, parents=[shared], help=help_text, description=help_text)

    p = cmd("init", "create <footage dir>/edit/<name>/ for a recording")
    p.add_argument("main", help="screen recording with the voice")
    p.add_argument("--camera", help="face-camera file recorded alongside")
    p.add_argument("--name", required=True, help="video name; names the edit root and timelines")

    p = cmd("silences", "detect (once) and summarise silences in the main audio")
    p.add_argument("--refresh", action="store_true", help="detect again with spec.json settings")

    p = cmd("snap", "move edl.json range edges into silences, padded")
    p.add_argument("--dry-run", action="store_true", help="report without writing edl.json")

    cmd("sync-script", "write resolve/sync.py (align camera to main by waveform)")

    p = cmd("set-offset", "record the camera offset from the sync result")
    p.add_argument("frames", type=int, help="camera frame = main frame - FRAMES")
    p.add_argument("--at", type=float, metavar="SECONDS", help="from this main-source time on (drift)")

    p = cmd("build", "validate edl.json, write resolve/plan_vN.json and build_vN.py")
    p.add_argument("--section", help="only this section's ranges, as its own timeline")
    p.add_argument("--version", type=int, help="version number (default: next)")
    p.add_argument("--no-camera", action="store_true", help="leave V2 empty")

    cmd("slots", "write slots/<id>/slot.json for every overlay")

    p = cmd("finalize", "encode a raw render to the slot's final spec (NVENC)")
    p.add_argument("raw", help="raw render (any format ffmpeg reads)")
    p.add_argument("--slot", required=True, help="slots/<id> directory")
    p.add_argument("--input-matrix", choices=["auto", "bt601", "bt709"], default="auto",
                   help="YUV matrix of the raw render (auto: its tag; untagged = bt601)")
    p.add_argument("--input-range", choices=["auto", "tv", "pc"], default="auto",
                   help="YUV range of the raw render (auto: its tag; untagged = tv)")
    p.add_argument("--dry-run", action="store_true", help="print the ffmpeg command only")

    p = cmd("check", "verify a render against its slot; writes a contact sheet")
    p.add_argument("file")
    p.add_argument("--slot", required=True, help="slots/<id> directory")
    p.add_argument("--draft", action="store_true", help="check against the draft spec")

    p = cmd("strip", "filmstrip + waveform PNG of a source range or around a cut")
    p.add_argument("video", nargs="?")
    p.add_argument("start", nargs="?", type=float)
    p.add_argument("end", nargs="?", type=float)
    p.add_argument("--cut", type=int, metavar="K", help="the assembled output around cut K")
    p.add_argument("--around", type=float, default=2.0, metavar="SECONDS")
    p.add_argument("--version", type=int)
    p.add_argument("-o", "--output", metavar="PNG")
    p.add_argument("--frames", type=int, default=10, help="filmstrip frames (default 10)")

    p = cmd("words", "kept words in output order, numbered for subtitle cues")
    p.add_argument("--version", type=int)
    p.add_argument("--section")
    p.add_argument("--json", action="store_true")

    p = cmd("srt", "turn cues.json into a checked SRT on the timeline's timecode")
    p.add_argument("cues", help='[{"from": i, "to": j, "text": "..."}] over `words` indices')
    p.add_argument("-o", "--output", metavar="SRT")
    p.add_argument("--version", type=int)
    p.add_argument("--section")
    p.add_argument("--start-tc", metavar="HH:MM:SS:FF", help="timeline start (default spec)")

    p = cmd("readback-script", "write resolve/readback_vN.py (export the timeline as OTIO)")
    p.add_argument("--version", type=int)

    p = cmd("verify-timeline", "compare the OTIO readback with plan_vN.json")
    p.add_argument("--version", type=int)
    p.add_argument("--otio", metavar="PATH")

    p = cmd("verify-audio", "transcribe the cut audio and diff it with the kept words")
    p.add_argument("--version", type=int)
    return top


def _slot_root(args):
    """Edit root for slot commands, from the cwd or else the slot's spec path."""
    try:
        return find_root(args.root)
    except UsageError:
        slot = Path(args.slot)
        data = read_json(slot / "slot.json" if slot.is_dir() else slot)
        return Root(Path(data["spec"]).parent)


def dispatch(args):
    from . import build, encode, project, slots, strip, subtitles, verify

    c = args.command
    if c == "init":
        return project.run_init(args.main, args.camera, args.name)
    if c in ("finalize", "check"):
        root = _slot_root(args)
        if c == "finalize":
            return encode.run_finalize(
                root, args.raw, args.slot, args.input_matrix, args.input_range, args.dry_run
            )
        return encode.run_check(root, args.file, args.slot, args.draft)
    if c == "strip":
        return strip.run_strip(
            args.video, args.start, args.end, args.output, args.frames,
            args.cut, args.around, args.version, args.root,
        )
    root = find_root(args.root)
    if c == "silences":
        return build.run_silences(root, args.refresh)
    if c == "snap":
        return build.run_snap(root, args.dry_run)
    if c == "sync-script":
        return project.run_sync_script(root)
    if c == "set-offset":
        return project.run_set_offset(root, args.frames, args.at)
    if c == "build":
        return build.run_build(root, args.section, args.version, args.no_camera)
    if c == "slots":
        return slots.run_slots(root)
    if c == "words":
        return subtitles.run_words(root, args.version, args.section, args.json)
    if c == "srt":
        return subtitles.run_srt(
            root, args.cues, args.output, args.version, args.section, args.start_tc
        )
    if c == "readback-script":
        return build.run_readback_script(root, args.version)
    if c == "verify-timeline":
        return verify.run_verify_timeline(root, args.version, args.otio)
    if c == "verify-audio":
        return verify.run_verify_audio(root, args.version)
    raise UsageError(f"unknown command {c}")


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        code, payload = dispatch(args)
    except ToolError as err:
        eprint(err)
        print(json.dumps({"ok": False, "error": str(err)}, ensure_ascii=False, indent=2))
        return err.exit_code
    except KeyboardInterrupt:
        return 130
    if isinstance(payload, str):
        sys.stdout.write(payload)
    else:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    return code if code is not None else EXIT_FAIL
