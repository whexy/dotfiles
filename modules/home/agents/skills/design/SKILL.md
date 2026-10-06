---
name: design
description: Wenxuan's rules for user interfaces and documentation. Use when designing or building a UI, or writing, restructuring, or reviewing docs such as a README, guide, or runbook.
---

# Personal Design

Use these rules for my personal projects and whenever I explicitly ask you to
design or write something.

If you are modifying an existing project with an established design language
or documentation structure, follow that project's conventions instead unless I
explicitly ask otherwise. Still apply the wording rules below.

When you brief a subagent to do this work, pass these rules on.

## The shared rule: everything earns its place

I am a knowledgeable reader with little time. Every piece of text, every
section and every element must give me information I need. If removing it does
not make the interface harder to use or the document harder to follow, remove
it. Whitespace is better than meaningless prose; a link is better than a
repeated explanation.

## Interfaces

### Pattern 0 — No useless text

Text must provide useful information.

Delete persistent text that only:

- explains an obvious UI
- decorates empty space
- adds mood or fake branding
- repeats information already conveyed visually
- teaches something the user only needs to learn once

Never invent copy just to complete a layout.

Avoid AI-style decorative copy such as:

- "Your X, made simple."
- "A familiar face. A new story."
- "People. In motion."
- uppercase eyebrow text with no information
- unnecessary title + subtitle + description stacks

If instructions are only occasionally useful, use:

- first-use hints
- tooltips
- hover hints
- `?` / info controls
- contextual help

Persistent text should normally communicate actual:

- state
- data
- identity
- navigation
- actions
- constraints
- warnings
- consequences

## Documents

### Structure

- One page per reader goal. No two pages cover the same path; when two
  overlap, merge them or link one to the other.
- A README is a front door, not a second copy of the docs: what this is, why
  it matters, one way to start, and links. Anything longer lives on the docs
  site or in `docs/`.
- Lead with the main path. An alternative is one tip at the top, with its
  commands and a link, not a parallel section.
- The default path is what a real user does (for example, a real agent with
  their own key). Fallbacks for those who can't come after.
- Order sections in the order the reader acts. One step is one section:
  "clone, install, add keys, check" is a single "Set up" section if the reader
  does it in one go.
- Variants of one step are tabs or a sentence, not separate sections.

### What goes where

- Don't explain what a command does internally. Say what to run and what the
  reader gets.
- Prerequisites: one line each, saying what, a short why, and a link.
- Tables, measurements, platform caveats and edge cases go on their own page,
  linked from where they matter.
- Troubleshooting goes to a troubleshooting page, not into the happy path.
- Help that only some readers need goes in a collapsible block whose title
  says what is inside.

### Wording

- Never use a term before saying what it is.
- Say plainly what is optional before listing the options.
- Quantities say what they count ("the entire pilot dataset", not "every
  task").
- One point per paragraph: do this, then the alternative.
- Lists stay short. A bullet that needs a second sentence to be understood is
  a paragraph, or it is too detailed for this page.

### Accuracy

- Run every command you document and show only output you actually saw. Never
  invent output, flags, or versions.
- When moving content, keep it somewhere, and fix every inbound link and
  anchor.
- Don't write these rules into the project. They are for writing the
  documentation, not part of it.
