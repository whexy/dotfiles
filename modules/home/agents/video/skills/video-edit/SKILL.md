---
name: video-edit
description: Edit a recorded talking-head video into a new DaVinci Resolve timeline with the video-edit CLI - cuts from a whisper transcript snapped to silences, camera sync, B-roll from slot subagents, verification and SRT subtitles. Use when editing a recorded video into a Resolve timeline.
---

# Video edit

The user records a screen recording with their voice (the main source) and
a separate face-camera file, both 4K60 with audio, on a Windows drive such
as `/mnt/d/Records`. You deliver a new Resolve timeline and an SRT; the user
finishes the edit in DaVinci Resolve Studio on Windows.

`video-edit` does every deterministic step: it validates cuts, does all
frame math, writes the Python that Resolve runs, defines B-roll slots,
encodes and checks renders, and writes subtitles. You make the editorial
decisions. Never hand-write frame math or Resolve code.

Every command runs inside the edit root, `<footage dir>/edit/<name>/`, which
`init` creates. Each prints one JSON result on stdout (`words` prints text)
and progress on stderr. Exit codes: `0` ok, `1` checked and found problems
(listed in the JSON), `2` usage, `3` media/ffmpeg, `4` transcribe failed,
`5` `OPENAI_API_KEY` missing.

## Running scripts in Resolve

`build`, `sync-script` and `readback-script` write a script under `resolve/`
and print `run` and `timeout`. Call the Resolve MCP tool `run_script_unsafe`
with `script` set to `run` and `timeout` set to 60. The result is a JSON
string; `"ok": false` comes with an `error`.

Scripts act on the project open in Resolve. Before the first one, check
with `get_resolve_status` (or `launch_resolve`) and confirm that the open
project is the one the user named. Never create, switch or delete projects
without asking.

## Workflow

### 1. Set up and transcribe

```sh
video-edit init /mnt/d/Records/talk.mkv --camera /mnt/d/Records/cam.mkv --name "AI Workflow"
cd "/mnt/d/Records/edit/AI Workflow"
transcribe /mnt/d/Records/talk.mkv --format json -o transcripts/talk.json
video-edit silences
```

Transcribe once, with no `--language` or `--context`. Read it as text with
`transcribe transcripts/talk.json --from-json`. `silences` detects the
pauses that every cut is judged against and caches them.

### 2. Propose, then wait

Read the whole transcript. Propose the strategy in plain English: what
goes, what stays, the sections, and where B-roll would help, each as an
animation or as real footage. Wait for the user's approval before writing
`edl.json`.

### 3. Write the cut list and snap it

`edl.json` lists the kept ranges in output order, in main-source seconds,
and the B-roll overlays:

```
{"version": 1, "name": "AI Workflow",
 "ranges": [{"start": 12.34, "end": 56.78, "section": "S01", "reason": "...", "quote": "..."}],
 "overlays": [{"slot": "G1", "anchor": 123.45, "lead": 0.8, "duration": 6.0, "reason": "..."}]}
```

An overlay is full-screen B-roll on V3. `anchor` is the main-source time of
the payoff word; the overlay starts `lead` seconds before that word's output
time and must lie inside the kept output. Slot ids are letters, digits, `-`
and `_`.

Propose edges from the transcript, then always run `video-edit snap`. It
moves each edge into the nearest silence: in-points about 0.09 s before
speech, out-points about 0.25 s after. Edges it lists under `speech` are in
continuous speech; look at each with `strip` before keeping it. Whisper word
edges are not reliable cut points on this material. `"lock": true` on a
range keeps its edges exactly as written.

### 4. Sync the camera

Run `video-edit sync-script` in Resolve, then record the result's
`camera_offset_frames` with `video-edit set-offset N` (camera frame = main
frame − N). If the face drifts out of sync later in the video, add
`set-offset N --at SECONDS` from that point on.

### 5. Build

`video-edit build` validates the cut list and writes `resolve/plan_vN.json`
and `resolve/build_vN.py`. Run the script: it creates the timeline
`<name> agent vN` with main on V1/A1, the camera mirroring every cut on V2,
and a marker per overlay. Its result has `ok: true` when the timeline ends
on the planned frame. `--section S` builds one section as its own timeline.

### 6. B-roll

A slot is one B-roll clip. `video-edit slots` writes `slots/<id>/slot.json`
with its length, sizes and the speech under it, already on the slot's own
clock. Write `slots/<id>/brief.md` from the template below, saying when a
slot is real footage, which the slot agent generates with Studio. Then spawn
one subagent per slot, all in parallel, with your harness's subagent tool
(Claude Code's Agent tool, OpenCode's task tool, or T3's `delegate_task`).

When they finish, build again. Only slots whose newest output passed
`check` against the current cut are placed; the rest are listed under
`broll.pending` with the reason.

### 7. Verify

```sh
video-edit readback-script        # run it in Resolve: exports the timeline as OTIO
video-edit verify-timeline        # frame-by-frame diff against the plan
video-edit verify-audio           # transcribes the cut audio, diffs it with the kept words
video-edit strip --cut 12         # filmstrip + waveform around a flagged cut
```

Look at strips only for flagged cuts. Fix `edl.json`, snap, build a new
version, and verify again. Stop after three fix passes and report what is
left.

### 8. Subtitles

`video-edit words` prints the kept words of the latest build, numbered. Write
`subtitles/cues.json` as `[{"from": i, "to": j, "text": "..."}]`: one cue per
semantic line, every word in exactly one cue, in order. Write the text you
mean, fixing misheard words; timings come from the words. Then run
`video-edit srt subtitles/cues.json` and fix what it reports.

Product names whisper mishears go in `spec.json` `glossary` (for example
`"telscope": "Tailscale"`); `srt` applies them to cue text. The user inserts
the SRT by hand.

### 9. Hand off

Append to `project.md`: the approved strategy, the latest version, decisions
the user made, and open issues. Tell the user the timeline name, the SRT
path and anything verification could not fix.

## Rules

- Cut in silences: snap before every build.
- Never transcribe a cached source again.
- Never modify a timeline: every build makes a new version.
- Never touch the subtitle track through the API.
- Always pass `timeout` to `run_script` and `run_script_unsafe`.
- No per-item loops in Resolve; generated scripts use batch calls.
- Keep every output inside the edit root.
- Slot subagents never call Resolve and never edit `style/`.
- Never re-render a slot that passed.

## The user's preferences

- No text in B-roll, Chinese or otherwise, unless `spec.json`
  `rules.textWhitelist` allows it.
- Render on the GPU.
- Never re-record or re-render finished clips.
- Subtitles break lines by meaning, not by length.

## Brief template

```
Render B-roll slot <id> for "<video name>": <one sentence: what the viewer should understand>.

Read the `broll` skill first. Inputs:
- slot: <root>/slots/<id>/slot.json. Its beats, phrases and anchor are already
  in the slot's own seconds and frames; use them as they are and never
  convert times yourself.
- spec: <root>/spec.json
- style: <root>/style/ (read-only)

Voiceover: "<slot.json voiceover>"
Land on: <anchor word and time>, <key phrases and their times>

Do not: show any text, numbers or labels; edit style/ or anything outside
slots/<id>/; call Resolve; render on the CPU.

Deliver: slots/<id>/out/<id>_vN.mp4 from `video-edit finalize` that passes
`video-edit check`, and slots/<id>/report.md with what it shows, the beats
it uses and the check result.

Do not ask questions. Decide, and note your assumptions in report.md.
```

## Commands

| Command                                                                               | Does                                                           |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `init MAIN --name NAME [--camera CAM]`                                                | creates the edit root, `sources.json`, `spec.json`, `style/`   |
| `silences [--refresh]`                                                                | detects pauses at the noise floor + 9 dB                       |
| `snap [--dry-run]`                                                                    | moves range edges into silences                                |
| `sync-script` / `set-offset N [--at S]`                                               | camera alignment                                               |
| `build [--section S] [--version N] [--no-camera]`                                     | plan and build script                                          |
| `slots`                                                                               | `slots/<id>/slot.json` per overlay                             |
| `finalize RAW --slot DIR [--footage] [--input-matrix auto\|bt601\|bt709] [--dry-run]` | NVENC encode to `out/<id>_vN.mp4`; `--footage` trims and crops |
| `check FILE --slot DIR [--draft]`                                                     | spec check plus contact sheet                                  |
| `strip VIDEO START END` / `strip --cut K`                                             | filmstrip and waveform PNG                                     |
| `words [--section S]` / `srt CUES [-o FILE] [--start-tc TC]`                          | subtitles                                                      |
| `readback-script` / `verify-timeline` / `verify-audio`                                | verification                                                   |
