# Visual explainer

The goal is to make understanding easier through a bespoke page shown inline in
the T3 Code thread. Make the mechanism, relationships, or changes over time
visible. Use judgment about scope: a focused diagram can be enough for a simple
relationship, while a process may benefit from a step-through or animation.

## Writing

Follow the wording rules of the `design` skill. On top of them, aim for "80%
of the way to ASD-STE100," rather than claiming formal compliance: short
sentences, concrete words, consistent terms, and explicit causal steps.
Preserve qualifications needed for accuracy.

## Diagrams

Make relationships, flow, and state visible. Label the important parts and
connect each diagram to the text beside it. Prefer inline SVG or HTML/CSS
diagrams; use a raster image only when it materially helps understanding.

## Build the page

1. Write one self-contained HTML document with inline `<style>` and
   `<script>`. Use controls, step-through sequences, sliders, or animations
   only when they teach something specific, and keep them accessible.
2. Fit the thread: leave `html`, `body`, and the outer element without a
   background, use a fluid width with no outer padding, card, or banner title,
   and style with T3's injected theme variables (`--background`,
   `--foreground`, `--muted`, `--card`, ...) so it follows light and dark
   mode. Give charts fixed pixel heights; never use `100vh` or
   `height: 100%` on `html` or `body`.
3. Check it with `html_preview` in both `dark` and `light`, and at about
   `390` wide for phones. Read the screenshot and console output, and confirm
   the teaching interactions work. Fix and repeat.
4. Publish it with `html_render`, using the preview's `contentHeight` as the
   height.
5. Write the final reply after the page. The reader already sees the page:
   do not announce it or restate it. Add only what the page does not say,
   such as caveats or where to look in the code.

If the `html_render` tool is not available, this session is not in T3 Code.
Build the same page as a file instead, and serve, check, and hand it over as
the `web-preview` skill describes.

## Other media

When the user asks for a video, create a bespoke explainer with visual
reasoning inspired by 3Blue1Brown: build intuition through diagrams, motion,
worked examples, and a coherent sequence. Render and inspect the actual video
rather than stopping at a script or storyboard. Use ElevenLabs narration only
when the user has provided access and authorized it for the task; otherwise
use a free or local speech tool, or none. If rendering is unavailable, state
the concrete limitation and agree on another medium rather than claiming a
video was produced.

Treat these artifacts as focused, disposable teaching tools. Spend effort on
what makes the topic understandable; do not expand them into unrelated apps.
