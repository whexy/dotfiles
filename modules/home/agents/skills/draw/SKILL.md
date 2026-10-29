---
name: draw
description: Draw on the live tldraw whiteboard through the `tldraw` MCP server. Use when the user asks for a diagram, sketch, flowchart, or whiteboard drawing, points at a draw room, or asks what is on the board; not for charts, images, or UI mockups.
---

# Draw

The `tldraw` MCP server reads and writes live tldraw rooms. Every change
broadcasts to anyone viewing the room, so the user watches the diagram appear
and can edit it alongside you. A room is at
`https://draw.at-basking.ts.net/room/<roomId>`.

## Before drawing

- Resolve the target room first: use the room the user named, or `list_rooms`
  to find existing ones. Omitting `roomId` targets the lobby, which everyone
  shares — only use it if the user means the lobby.
- `read_room` before changing a room with content in it, so new shapes land in
  empty space instead of on top of existing work, and updates use real
  shapeIds. Pass `pageId` to read one page. Each page reports its content
  `bounds` and each shape its page-space `bounds`; place new work outside
  them. Bounds marked `estimated` (text, bound or curved arrows) are guesses,
  so leave extra room around them.
- Pick a new `roomId` from the topic when the user wants a fresh board, and
  open the room URL for them if you can hand over a preview.

## Pages

- A room has one or more pages. `create_shapes` draws on the first page unless
  given a `pageId`.
- Spread a large diagram over pages, such as an overview and then one page per
  part: `create_page {name}` for each and pass its returned `pageId` to
  `create_shapes`. `rename_page` renames a page.
- Arrows only bind shapes on the same page. To move part of a diagram,
  `update_shapes` with `pageId` on its shapes and the arrows between them in
  one call; shapes inside a frame move with it.

## Layout

Coordinates are tldraw page units with y growing downward, on read and write,
including shapes inside frames. Reasonable defaults that read well at default
zoom:

- Leave at least 40 units between shapes; give a labeled box roughly
  220×80 or more so the text fits, and more for long labels.
- Flow left to right or top to bottom; align shapes on a shared grid instead
  of scattering them.
- Create all boxes in one `create_shapes` call with explicit `shapeId`s, then
  arrows bound with `fromId`/`toId` so they stay attached when the user drags
  things around; a bound end needs no coordinates. Free-floating `x1`–`y2`
  arrows are for annotations that bind to nothing.
- Use `text` shapes for titles, with `fontSize` in px and `maxWidth` to wrap a
  caption, and `note` shapes for asides.
- Styles:
  - `color` takes tldraw color names (`black`, `grey`, `light-violet`,
    `violet`, `blue`, `light-blue`, `yellow`, `orange`, `green`,
    `light-green`, `light-red`, `red`, `white`); `fill: "tint"` keeps colored
    boxes readable.
  - `dash` (`draw`, `solid`, `dashed`, `dotted`), `size` (`s` to `xl`), and
    `font` (`draw`, `sans`, `serif`, `mono`) default to the hand-drawn look;
    `dash: "solid"` with `font: "sans"` reads as a clean diagram.
  - `textAlign` and `verticalAlign` take `start`, `middle`, or `end`.
  - Arrows take `arrowheadStart`/`arrowheadEnd` (`none` at both ends draws a
    plain line), `kind: "elbow"` for right-angle routing, `bend` for a curve,
    and `text` for a label.
- The `create_shapes` and `update_shapes` input schemas list every field and
  allowed value. `search` looks up the tldraw Editor API by keyword, as
  background only: this MCP does not run Editor code.

## Changing shapes

- `update_shapes` patches shapes by `shapeId` with the fields of each shape's
  type. A field the type does not take is an error, so drop the read-only
  fields `read_room` adds (`bounds`, `parentId`, `isLocked`, and the extras on
  `unknown` shapes) before sending a read shape back.
- Rebind an arrow end with `fromId`/`toId`; `null` detaches it where it is
  drawn.
- Frames, images, and drawings read as `unknown`: they can be moved, but not
  restyled or created.
- Locked shapes cannot be changed or deleted; ask the user to unlock them.

## Care

Rooms are shared and unauthenticated: anyone on the tailnet can view and edit
them. Do not put secrets or credentials on the board. `delete_shapes` removes
bindings and children with the shape, `delete_page` removes a page with
everything on it, and there is no undo through the MCP — confirm with the user
before deleting shapes or pages you did not just create.
