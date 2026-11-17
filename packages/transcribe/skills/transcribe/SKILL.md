---
name: transcribe
description: Transcribe audio/video files with the transcribe CLI - free WeType segment-timed text by default, or OpenAI whisper-1 word-timed transcripts annotated with pauses, fillers and stumbles. Use when summarizing or taking notes on a recording, making SRT subtitles, or editing and planning cuts.
---

# Transcribe

`transcribe` turns an audio or video file into a timed transcript. It
has two backends; pick one per job, by whether you need word timing.

| `--backend`        | Use for                                                                                                       | Timing                                                                         | Cost and privacy                                            |
| ------------------ | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| `wetype` (default) | What a recording says: summaries, notes, rough subtitles                                                      | Segments only: pause-cut chunks of about 5-10 s. No words, fillers or stumbles | Free. The audio goes to Tencent (WeChat's WeType cloud ASR) |
| `whisper`          | Anything that needs word edges: editing narrator video, planning cuts, finding fillers, stumbles and dead air | Every word, with gaps, filler and stumble marks                                | OpenAI `whisper-1`, $0.006 per minute (~$0.36/hour)         |

Stay on the default unless word timing is actually required. When the
user says "use the WeType model", that means `--backend wetype`. Do not
send a recording to WeType if the user has said it must not leave their
machines or OpenAI; use `--backend whisper` then, or ask.

Long files are chunked at silence boundaries automatically (WeType at
most ~290 s per request, whisper ~10 min) and stitched; timestamps in
the output are always absolute.

## WeType

- Accuracy: character error rate is about 0-1% on clean Chinese, English
  and mixed speech, and about 8% on casual conversation. Numbers come back
  as digits, rare names are often garbled, and fillers (um, 嗯, 那个) are
  dropped, so the text is cleaner than what was said.
- `--language`, `--context` and `--pause` do not apply: WeType detects the
  language itself and takes no glossary.
- It is slow and serial: about 1 minute per 5 minutes of audio, one chunk
  at a time. A busy server (HTTP 429) is retried automatically.
- It is on the tailnet only (`wetype-asr.at-basking.ts.net`, or the tailnet
  relay on homes that run one). On a host off the tailnet it fails with
  exit 4; use `--backend whisper` there.
- Segments are contiguous: each runs to the next one's start, so a
  segment's edges are not pause edges.

## whisper-1

Word edges land about +/-0.2 s from the real pause edges: good enough to
decide what to cut, never a cut point. Snap every cut point to a detected
silence (`video-edit snap` does this when editing video; elsewhere run
ffmpeg `silencedetect` at the JSON's `silence.threshold_db`) and add
~0.15 s/0.25 s handles in the actual edit.

The text is whisper-1's, verbatim. Individual words may be misheard
(names, jargon, code-switched terms); read them against the surrounding
context when you interpret the transcript. Cutting decisions depend on
where words start and stop, not on perfect spelling.

- `--language CODE` hints the language (e.g. `zh`, `en`); omit to
  auto-detect, which handles code-switching better.
- `--context "..."` is whisper-1's glossary prompt (max ~224 tokens);
  list names/jargon you expect to hear to bias their spelling.
- For Chinese recordings pass neither: on the user's footage auto-detect
  got the language right and a glossary did not improve the text.
- `--pause SECONDS` (default 0.6) is the gap that starts a new segment.

## Setup

`transcribe` reads each backend's key from an agenix secret itself; do
not export one:

- WeType: `secrets/wetype-asr-transcribe-token.age`
- whisper: `secrets/openai-api-key.age` (a key with the Audio scope)

Exit 5 means the key is not on this machine (a home gets the WeType
token at its next dotfiles switch); exit 4 with `HTTP 401` means it was
rejected. Either way tell the user which secret; do not invent a key.
`transcribe --estimate FILE [--backend whisper]` prints duration and
cost without a key or any API calls; run it first on long files.

## Usage

```sh
transcribe talk.mp4                              # WeType, text to stdout
transcribe talk.mp4 --format srt -o talk.srt     # WeType subtitles
transcribe talk.mp4 --backend whisper --format json -o talk.json   # word-level data
transcribe talk.mp4 --backend whisper --context "Kubernetes, ArgoCD, Wenxuan"
transcribe --from-json talk.json --format srt    # re-render, no API call
```

Transcribe each source once to JSON and keep it; render the text view
and SRT from it with `--from-json`, which takes `--format`, `--pause`
(word-timed JSON only) and `--no-silence` but needs no key, API call, or
ffmpeg. Leave silence detection on for that one run: silences cannot be
added back from the JSON later, and without them long files are cut
every 270 s (WeType) or 600 s (whisper) even mid-word.

- `--silence-db DB` is the silence threshold in dBFS. The default, `auto`,
  is the audio's measured noise floor + 9 dB, or -35 dB when there is no
  floor to measure (mostly digital silence). Silences under 0.5 s are
  ignored. The JSON records the values used under `silence`.
- Progress goes to stderr; stdout carries only the transcript.

## Reading the output

A JSON result's `timing` is `word` (whisper) or `segment` (WeType).
Segment results have no `words` anywhere, and `video-edit` refuses them.

WeType text format, one segment per line:

```
[00:00.00-00:05.62] Four the commander, five method and discipline
[00:05.62-00:14.84] The moral law causes the people to be in complete accord with their ruler
```

whisper text format, one segment (split on pauses) per line:

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

`0` ok, `2` usage (or a `--from-json` file that is not transcribe JSON),
`3` media/ffmpeg problem, `4` API error or no route to WeType, `5` the
backend's key is not on this machine.
