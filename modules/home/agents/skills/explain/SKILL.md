---
name: explain
description: Read first when the user asks for an explanation, conceptual walkthrough, or help understanding a topic, code, or system. For explanations likely to need ten or more paragraphs, ask whether they want normal text or Andrej Karpathy style; otherwise answer directly in text unless they request an interactive explanation. Do not load for implementation, fixes, reviews, status updates, or incidental explanations in other work.
---

# Explain

Use this skill only when the user requests an explanation or help understanding
something, or explicitly invokes `explain`. Read it before preparing the
explanation. A request to build, fix, or review something does not activate this
skill merely because the response will describe the work.

## Choose the output format

Estimate the length needed to explain the topic thoroughly and clearly.

- If a thorough explanation fits in a few paragraphs, answer directly in normal text. Do not ask the user to choose a format.
- If the user specifically requests an interactive explanation or names a mode or medium, follow that request without asking them to confirm it.
- If the topic is complex enough that a thorough explanation is likely to require ten or more paragraphs, ask which mode they want:
  - **Normal:** A text reply using the agent's usual response style.
  - **Andrej Karpathy style:** A custom visual or interactive explanation, with clear writing inspired by ASD-STE100. Usually an interactive HTML page; diagrams or an explainer video may fit better.

Suggested question: "This topic needs a detailed explanation. Would you prefer normal text or Andrej Karpathy style: a visual or interactive explainer?"

Use an available user-input tool, or ask in a short reply if none is available.
This is a format preference, not permission to perform an external action.
Ask once per explanation request; a choice already made for this explanation
also covers follow-up questions about it. Do not ask again unless the user
changes the format or starts a separate explanation request.

While waiting, you may inspect relevant code or gather facts. Keep the format
choice pending before producing a long explanation. If the user declines to
choose or the input tool returns no answer, use normal text. Do not treat
elapsed time alone as confirmation or switch to a richer format without a
choice.

## Normal mode

Answer in the usual text style, respecting the user's requested depth and
structure. Do not impose controlled-language rules or generate a separate
artifact merely because this skill was loaded.

## Andrej Karpathy mode

The goal is to make understanding easier through a bespoke artifact. Choose the
medium that helps the user see the mechanism, relationships, or changes over
time. Honor a medium the user requested; otherwise favor an interactive HTML
page. Use judgment about scope: a focused diagram can be enough for a simple
relationship, while a process may benefit from animation or video.

### Writing

Follow the wording rules of the `design` skill. On top of them, aim for "80%
of the way to ASD-STE100," rather than claiming formal compliance: short
sentences, concrete words, consistent terms, and explicit causal steps.
Preserve qualifications needed for accuracy.

### Diagrams and images

Make relationships, flow, and state visible. Label the important parts and
connect the diagram to the explanation. Choose native diagrams or vector
visuals when they express the topic well; use generated images when a raster
illustration materially helps understanding.

### Interactive HTML

Create a complete, locally viewable HTML artifact, not just a code block or a
proposal. Use controls, step-through sequences, sliders, or animations when
they teach something specific. Give the page a clear visual hierarchy, readable
labels, and accessible controls. Prefer a self-contained page when practical.
Serve, check, and hand it over as the `web-preview` skill describes: confirm
its teaching interactions work, then give a tailnet link with a brief
orientation.

### Explainer videos

When video fits the topic or is requested, create a bespoke explainer with
visual reasoning inspired by 3Blue1Brown: build intuition through diagrams,
motion, worked examples, and a coherent sequence. Render and inspect the actual
video rather than stopping at a script or storyboard.

Use narration when helpful. Use an ElevenLabs API key only when the user has
provided access and authorized its use for the task. Otherwise consider a
suitable free or local speech tool; do not require paid narration. If rendering
or narration is unavailable, state the concrete limitation and agree on an
available medium rather than claiming a video was produced.

Treat these artifacts as focused, disposable teaching tools. Spend effort on
what makes the topic understandable; do not expand them into unrelated apps.
