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
  shapeIds.
- Pick a new `roomId` from the topic when the user wants a fresh board, and
  open the room URL for them if you can hand over a preview.

## Layout

Coordinates are tldraw page units with y growing downward. Reasonable defaults
that read well at default zoom:

- Leave at least 40 units between shapes; give a labeled box roughly
  220×80 or more so the text fits.
- Flow left to right or top to bottom; align shapes on a shared grid instead
  of scattering them.
- Create all boxes in one `create_shapes` call with explicit `shapeId`s, then
  arrows bound with `fromId`/`toId` so they stay attached when the user drags
  things around. Free-floating `x1`–`y2` arrows are for annotations that bind
  to nothing.
- Use `text` shapes for titles and `note` shapes for asides. `color` takes
  tldraw color names (`black`, `grey`, `light-violet`, `violet`, `blue`,
  `light-blue`, `yellow`, `orange`, `green`, `light-green`, `light-red`,
  `red`, `white`); `fill: "tint"` keeps colored boxes readable.
- When unsure about a shape prop or Editor capability, query the `search`
  tool instead of guessing — it runs JavaScript against the live spec.

## Care

Rooms are shared and unauthenticated: anyone on the tailnet can view and edit
them. Do not put secrets or credentials on the board. `delete_shapes` removes
bindings and children with the shape, and there is no undo through the MCP —
confirm with the user before deleting shapes you did not just create.
