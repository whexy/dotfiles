## Design rules (Frost)

This project uses Frost, the design language of www.whexy.com. Values
come from the wxstack Frost assets imported by `site/styles.css`; components and blocks are described
by the `frost` skill. TabOS uses a full-width workspace for terminal and
Wayland panes. Its terminal uses an ink surface and the shared dotfiles
terminal font. For UI work, use the `frost-page`,
`frost-component` and `frost-review` skills.

- Take every color, radius, shadow and font from `tokens.css`, and never write a hex code, px value or arbitrary `[...]` class outside it. A stray value is how a design drifts one screen at a time.
- Write semantic tokens (`text-ink-muted`, `bg-canvas`, `outline-accent`), not primitives (`text-neutral-500`). Names that say what a value is for survive a palette change.
- Use only the `neutral` grays. Warm or cool grays fight the colored glow behind the glass.
- Reach for a Frost class (`glass-card`, `panel`, `paper`, `btn-glass`, `segmented`, …) before writing utilities, and promote a pattern into `components.css` once it repeats three times. One definition keeps every instance identical.
- Put long-form text on `paper`, never on glass. Blurred, tinted backgrounds cost legibility over many paragraphs.
- Use `accent` (the dusty rose) only for link highlighting, focus rings, text selection and a selected chart range. A single functional color stays meaningful only if it is never decoration.
- Keep color decorative and behind glass: tints and blobs at low opacity, `-z-10`, with content in `relative z-10`. Text and controls stay neutral so the page reads calm.
- In charts, color means identity only: give each entity a `series-N` slot in order and keep it across the page, draw totals in `series-total`, and never color text. A hue that also meant size, rank or good/bad could no longer say which entity it is.
- Draw charts on `paper`, never on glass, following `references/charts.md` in the `frost` skill. Thin lines lose legibility over a blurred background.
- Give depth with light, not lines: hairline `black/5` borders and `shadow-sm shadow-black/5`, never heavy borders or dark shadows. Heavy edges break the frosted look.
- Keep reading content in the single `max-w-content` (720px) column; only pages built around charts use the full-width Dashboard shell. One column is the site's reading rhythm, and charts need the room.
- Make page-level surfaces square and edge to edge below `sm`, and step the radius down when nesting (3xl > 2xl > xl > lg). Phone screens are too narrow to spend on gutters, and nested equal radii look misaligned.
- Use `text-sm` as the UI size, `font-title` (Lato) for headings and controls, and `font-article` (Fira Sans) for reading text. Two families with fixed jobs keep chrome and content distinct.
- Animate with `duration-150` for color and `duration-200` for everything else, and never lift past `scale-[1.02]`. Calm motion is part of the look.
- Give every new interactive element the accent focus ring (`focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent`). Keyboard users need to see where they are.
- Use no green, amber or red to signal status; show unavailable data in neutral tones inside the usual component shape. The system has no status colors yet, and color used loosely stops meaning anything.
- Build only states and variants that exist in the component reference. An agent that sees a documented-but-unbuilt variant will keep reaching for it.
- When a decision is listed in the open questions (dark mode, status colors, a new block, …), ask the user before choosing. Reasonable guesses quietly become the design.
