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

Costs about $0.006 per minute of media (~$0.36/hour). Word timestamps
are approximate (+/-0.1-0.5 s): good enough to decide what to cut, not
frame-accurate. Snap cut points to silence and add ~0.15 s/0.25 s
handles in the actual edit (ffmpeg, DaVinci Resolve, etc.).

The text is whisper-1's, verbatim. Individual words may be misheard
(names, jargon, code-switched terms); read them against the surrounding
context when you interpret the transcript. Cutting decisions depend on
where words start and stop, not on perfect spelling.

## Setup

Needs `OPENAI_API_KEY` in the environment (a key with the Audio scope).
If a command exits 5, the key is missing: ask the user to export it, do
not invent one. `transcribe --estimate FILE` prints duration and cost
without a key or any API calls; run it first on long files.

## Usage

```sh
transcribe talk.mp4                              # annotated text to stdout
transcribe talk.mp4 --format json -o talk.json   # full word-level data
transcribe talk.mp4 --format srt -o talk.srt     # subtitles / Resolve import
transcribe talk.mp4 --context "Kubernetes, ArgoCD, Wenxuan"
```

- `--language CODE` hints the language (e.g. `zh`, `en`); omit to
  auto-detect, which handles code-switching better.
- `--context "..."` is whisper-1's glossary prompt (max ~224 tokens);
  list names/jargon you expect to hear to bias their spelling.
- `--pause SECONDS` (default 0.6) is the gap that starts a new segment.
- Progress goes to stderr; stdout carries only the transcript.

## Reading the output

Text format, one segment per line:

```
[00:00.00-00:04.00] So {basically,} {um,} {{the}} {{the}} plan is to deploy Kubernetes today. <pause 1.8s>
[00:05.80-00:06.80] (pause 1.8s) Then we review.
# silence without speech: [00:04.20-00:07.00] 2.8s
```

- `{word}` filler (um/uh/like/basically/嗯/那个/然后…), `{{word}}` stumble
  (immediately repeated word), `<pause Xs>` long pause inside a segment,
  `(pause Xs)` silence before the segment. `# silence without speech`
  lines are silent stretches with no words at all (dead air, music).
- JSON gives every word `start`/`end`/`gap_after` plus `filler`/`stumble`
  flags.

For cut planning: treat a filler plus its surrounding pauses as one cut
region, cut only the first take of a `{{stumble}}`, and prefer cutting in
`(pause …)` gaps. False starts and repeated whole sentences are not
marked; spot them in the text and use the segment timestamps.

## Exit codes

`0` ok · `2` usage · `3` media/ffmpeg problem · `4` API error · `5`
`OPENAI_API_KEY` not set.
