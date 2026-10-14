# B-roll style

Every slot in this video follows these rules, so the cutaways read as one
set. `tokens.css` holds the values; import it rather than copying them.
This folder is read-only for slot workers.

## Frame

- Full-screen and opaque: the first and last frames are complete
  pictures, with no fade from or to transparency. The editor cuts to B-roll
  hard.
- The background is `--bg` (#0e0f11) with the dot grid from `.stage`.

## Palette

| Token                  | Use                                               |
| ---------------------- | ------------------------------------------------- |
| `--bg`                 | background                                        |
| `--panel`, `--panel-2` | cards and their raised parts                      |
| `--line`               | borders and connectors at rest                    |
| `--text`               | primary shapes and icons                          |
| `--muted`, `--dim`     | secondary shapes, inactive states                 |
| `--green`              | success, the recommended path, "on"               |
| `--amber`              | attention, in progress, trade-offs                |
| `--red`                | failure, cost, "off"                              |
| `--blue`, `--violet`   | neutral categories when green/amber/red would lie |

## Motion

- No text by default: no words, labels, numbers or captions, in any
  language. `spec.json` `rules.text` and `rules.textWhitelist` are the only
  exceptions.
- Eased motion, never linear: enter with `--ease-out`, move with
  `--ease-in-out`, and use `--ease-back` only for small pops.
- One new element at a time, each entering on a beat from `slot.json`
  (`beats`, `phrases`, `anchor`).
- Entrances take about `--enter` (0.6 s).
