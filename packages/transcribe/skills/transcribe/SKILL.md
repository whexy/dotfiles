---
name: transcribe
description: Transcribe audio/video files with the transcribe CLI into word-timed transcripts annotated with pauses, fillers and stumbles. Use when editing or planning cuts for a recording, summarizing spoken content, or generating SRT subtitles.
---

# Transcribe

`transcribe` turns an audio or video file into a word-by-word timed
transcript built for editing decisions, using OpenAI `whisper-1` (the
only model that returns word timestamps). Long files are chunked at
silence boundaries automatically; timestamps in the output are always
absolute.

Costs about $0.006 per minute of media (~$0.36/hour). Word edges land
about +/-0.2 s from the real pause edges: good enough to decide what to
cut, never a cut point. Snap every cut point to a detected silence
(`video-edit snap` does this when editing video; elsewhere run ffmpeg
`silencedetect` at the JSON's `silence.threshold_db`) and add
~0.15 s/0.25 s handles in the actual edit.

The text is whisper-1's, verbatim. Individual words may be misheard
(names, jargon, code-switched terms); read them against the surrounding
context when you interpret the transcript. Cutting decisions depend on
where words start and stop, not on perfect spelling.

## Setup

`transcribe` reads its OpenAI key (one with the Audio scope) from the
agenix secret `secrets/openai-api-key.age` itself; do not export
`OPENAI_API_KEY`. If a command exits 5 (key missing) or 4
with `HTTP 401` (key rejected), ask the user to set that secret with
`agenix -e openai-api-key.age -i ~/.ssh/agenix_ed25519` (run in `secrets/`)
and rebuild; do not invent a key. `transcribe --estimate FILE` prints duration and cost
without a key or any API calls; run it first on long files.

## Usage

```sh
transcribe talk.mp4                              # annotated text to stdout
transcribe talk.mp4 --format json -o talk.json   # full word-level data
transcribe talk.mp4 --format srt -o talk.srt     # subtitles / Resolve import
transcribe talk.mp4 --context "Kubernetes, ArgoCD, Wenxuan"
transcribe --from-json talk.json --format srt    # re-render, no API call
```

When editing, transcribe each source once to JSON and keep it; render
the text view and SRT from it with `--from-json`, which takes `--format`,
`--pause` and `--no-silence` but needs no key, API call, or ffmpeg.
Leave silence detection on for that one run: silences cannot be added
back from the JSON later.

- `--language CODE` hints the language (e.g. `zh`, `en`); omit to
  auto-detect, which handles code-switching better.
- `--context "..."` is whisper-1's glossary prompt (max ~224 tokens);
  list names/jargon you expect to hear to bias their spelling.
- For Chinese recordings pass neither: on the user's footage auto-detect
  got the language right and a glossary did not improve the text.
- `--pause SECONDS` (default 0.6) is the gap that starts a new segment.
- `--silence-db DB` is the silence threshold in dBFS. The default, `auto`,
  is the audio's measured noise floor + 9 dB, or -35 dB when there is no
  floor to measure (mostly digital silence). Silences under 0.5 s are
  ignored. The JSON records the values used under `silence`.
- Progress goes to stderr; stdout carries only the transcript.

## Reading the output

Text format, one segment per line:

```
[00:00.00-00:04.00] So {basically,} {um,} {{the}} {{the}} plan is to deploy Kubernetes today. <pause 1.8s>
[00:05.80-00:06.80] (pause 1.8s) Then we review.
# silence without speech: [00:04.20-00:07.00] 2.8s
```

- `{word}` filler (um/uh/like/basically/嗯/那个/然后…), `{{word}}` stumble
  (a word or phrase said twice in a row, both takes marked),
  `<pause Xs>` long pause inside a segment, `(pause Xs)` silence before
  the segment. `# silence without speech` lines are silences no word
  gap accounts for: dead air, music, or a pause whisper stretched a
  word over.
- A doubled single hanzi (刚刚, but also a stutter like 我我) and 一X一X
  (一台一台) are not marked as stumbles.
- JSON gives every word `start`/`end`/`gap_after` plus `filler`/`stumble`
  flags.

For cut planning: treat a filler plus its surrounding pauses as one cut
region, cut only the first take of a `{{stumble}}` (after checking the
sentence: 虚拟机，虚拟机里面… repeats on purpose), and prefer cutting in
`(pause …)` gaps. False starts and repeated whole sentences are not
marked; spot them in the text and use the segment timestamps.

## Exit codes

`0` ok · `2` usage (or a `--from-json` file that is not transcribe
JSON) · `3` media/ffmpeg problem · `4` API error · `5`
`OPENAI_API_KEY` not set.
