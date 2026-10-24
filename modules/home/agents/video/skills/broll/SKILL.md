---
name: broll
description: Fill one B-roll slot for the video-edit pipeline with an animation or generated footage. Use when assigned a `slots/<id>/` directory to fill.
---

# B-roll slot

You turn one slot into a finished clip: a full-screen, opaque animation or
piece of footage that plays over part of the voiceover. Run every command from
the edit root, the directory holding `spec.json`, `style/` and `slots/`. `<id>`
is your slot's id.

## Inputs

- `slots/<id>/brief.md`: what the clip must show.
- `slots/<id>/slot.json`, written by `video-edit slots`:
  - `frames`, `fps`, `width`, `height`, `duration`: the final spec.
  - `draft`: the draft's frames, fps and size.
  - `beats`: the words and phrases spoken during the clip, in seconds and
    frames counted from the clip's first frame.
  - `voiceover`: the voiceover for this window.
  - `timeline_offset_frames`: where the clip sits on the edit timeline; your
    timing never needs it.
  - `spec`: the path to `spec.json`.
- `spec.json`: the edit's spec, including any on-screen text it allows.
- `style/`: the edit's look, `tokens.css` plus a `README.md` on using it.

## Choose an engine

Use HyperFrames (HTML, CSS and GSAP, rendered frame-exact) by default. Use
ManimGX for math, graphs and diagrams that morph. When the brief asks for real
footage, generate it with Studio instead; see
[Footage from Studio](#footage-from-studio).

- HyperFrames: read `hyperframes-core/SKILL.md` and
  `hyperframes-animation/SKILL.md` in `~/.local/share/video-edit/docs/hyperframes/`.
  Skip the `hyperframes` entry skill; its interview, usage and upgrade steps
  are for interactive sessions. Where the docs say `npx hyperframes` or
  `npm run`, run `hyperframes` itself: `npx` fetches a copy whose Chrome cannot
  start here.
- ManimGX: `manimgx` is ManimGX 0.1.1, Manim CE's API (`import manimgx as m`)
  on a GPU renderer. Typst sets `Tex` and `MathTex`; there is no LaTeX. In
  `~/.local/share/video-edit/docs/manimgx/`, read `SKILL.md` and
  `user-guide/coming-from-manim-ce.md`; the other guides in `user-guide/` and
  the scenes in `examples/` cover each feature.

## Build

Build in `slots/<id>/src/`. Take every time from `slot.json`: the clip lasts
`duration` exactly as written, and each motion starts at a beat's `seconds`.
Never convert frames to seconds or between frame rates.

For HyperFrames, author at the draft size; the final render scales the same
composition up, so the approved draft is what ships. `--resolution` takes the
draft size's preset (`1080p` is 1920x1080):

```sh
hyperframes init slots/<id>/src --example blank --resolution 1080p --non-interactive
cp ~/.local/share/video-edit/vendor/gsap.min.js slots/<id>/src/gsap.min.js
cp -R style slots/<id>/src/style
```

Then, in `index.html`:

- Replace the CDN GSAP `<script>` with `<script src="gsap.min.js"></script>`
  and link `style/tokens.css`. Nothing may load from the network.
- Set the root `data-duration` to `duration`.
- For each web font family, add this check, so `hyperframes check` fails when
  the font did not load:

  ```js
  document.fonts.load('1em "Family"').then((faces) => {
    if (faces.length === 0) throw new Error('font "Family" did not load');
  });
  ```

For ManimGX, write `slots/<id>/src/scene.py`; its `run_time`s and `wait`s come
from the beats' seconds and add up to `duration`.

## Render and check

1. HyperFrames only: `hyperframes check slots/<id>/src` must pass.
2. Render the draft at the `draft` spec:

   ```sh
   hyperframes render slots/<id>/src --gpu --fps <draft fps> --output slots/<id>/draft/<id>.mp4
   manimgx render slots/<id>/src/scene.py <Scene> -r <w>x<h> --fps <draft fps> \
     -o slots/<id>/draft/<id>.mp4
   ```

   ManimGX also writes a storyboard beside the video and lists layout
   problems; fix the ones the brief does not intend.

3. Run `video-edit check <draft> --slot slots/<id> --draft`, then look at the
   contact sheet it produces. Fix and repeat from step 1 until the check
   passes and the sheet shows what the brief asks for.
4. Render the final at the full spec. `--resolution` takes the final size's
   preset (`4k` is 3840x2160):

   ```sh
   hyperframes render slots/<id>/src --gpu --fps <fps> --resolution 4k --output slots/<id>/render/<id>.mp4
   manimgx render slots/<id>/src/scene.py <Scene> -r <width>x<height> --fps <fps> \
     -o slots/<id>/render/<id>.mp4
   ```

5. Run `video-edit finalize <raw> --slot slots/<id>`. It writes
   `slots/<id>/out/<id>_vN.mp4`.
6. Run `video-edit check slots/<id>/out/<id>_vN.mp4 --slot slots/<id>`. Once it passes,
   render nothing more unless the brief changes.
7. Write `slots/<id>/report.md`: the clip's path, the engine, every
   interpretation you chose, and the check results.

## Footage from Studio

The `studio` MCP server generates video on the studio's GPU Workers. Its clips
run 5 to 14.375 s at 24 fps, so it fills slots of at most 14 s. Footage does
not land on beats: pick one shot that works across the whole slot.

1. Write the prompt to `slots/<id>/src/prompt.md`: the subject, action,
   setting, camera and light of one continuous shot. Ask for no text, signs
   or captions unless `spec.json` allows the text.
2. `create_session` titled `<video name> <id>`, then `generate_video` with the
   prompt and `duration` set to the slot's `duration` plus 0.1, at least 5.
   Leave out `mode`, `width` and `height`: from a prompt alone Studio uses its
   largest canvas, 1344x768. Don't upload pictures; `upload_image` sends the
   file as base64 inside the tool call.
3. Poll `get_generation` until it ends. Download a completed clip's
   `video_url` at once, since the link expires after 15 minutes, numbering
   each generation:

   ```sh
   curl -fsSL -o slots/<id>/render/<id>_g1.mp4 '<video_url>'
   ```

4. Continue from step 5 of [Render and check](#render-and-check), passing
   `--footage` to `video-edit finalize`: it cuts the clip to the slot's length
   and crops it to the slot's aspect. Look at the contact sheet `check`
   writes. If the footage misses the brief, change the prompt and generate
   again, three generations at most, then deliver the closest and say what is
   off.

`report.md` also gives the final prompt and the generation's id and seed.

## Rules

- Render frame-exact with the commands above. Never record a screen or a
  browser tab in real time: it drops frames, and 11 of 27 clips came out
  short that way.
- Every HyperFrames render passes `--gpu`.
- Write only inside `slots/<id>/`; only `video-edit finalize` writes to
  `out/`. Never edit `style/`.
- No text on screen unless `spec.json` allows that text.
- In animations, ease every motion, never linear. Bring in one new element
  at a time. Hold the final frame for at least 1 s.
- Never call the Resolve MCP.
- Don't ask questions. Take the obvious reading of the brief and note it in
  `report.md`.
