"""Convert Ghostty theme files into Rex Beta custom themes.

Usage: rex-themes.py THEMES_DIR SPECS

SPECS is a JSON list of {"id", "name", "appearance"}, where each name is a
file in THEMES_DIR. Prints the JSON list Rex stores in Workspace.customThemes,
in the shape its own Ghostty theme import writes.
"""

import json
import sys
from pathlib import Path

# Rex's name for each Ghostty color key a theme must set.
COLORS = {
    "background": "background",
    "foreground": "foreground",
    "cursor-color": "cursor",
    "cursor-text": "cursorText",
    "selection-background": "selectionBackground",
    "selection-foreground": "selectionForeground",
}


def color(value, path):
    digits = value.removeprefix("#")
    if len(digits) != 6:
        sys.exit(f"{path}: {value!r} is not an #rrggbb color")
    red, green, blue = (int(digits[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return {"red": red, "green": green, "blue": blue, "alpha": 1, "colorSpace": "srgb"}


def theme(path, spec):
    named, indexed = {}, {}
    for line in path.read_text().splitlines():
        key, sep, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not sep or key.startswith("#"):
            continue
        if key == "palette":
            index, _, value = value.partition("=")
            indexed[int(index)] = color(value.strip(), path)
        elif key in COLORS:
            named[COLORS[key]] = color(value, path)

    missing = [k for k in COLORS.values() if k not in named]
    missing += [f"palette {i}" for i in range(16) if i not in indexed]
    if missing:
        sys.exit(f"{path}: missing {', '.join(missing)}")

    return {
        "id": spec["id"],
        "name": spec["name"],
        "appearance": spec["appearance"],
        "source": {"ghosttyFile": {"fileName": spec["name"]}},
        "createdAt": 0,
        "palette": named
        | {
            "ansi": [indexed[i] for i in range(16)],
            "paletteBase": {str(i): c for i, c in indexed.items() if i >= 16},
            "paletteGenerate": False,
            "paletteHarmonious": False,
            "paletteOverrides": {},
        },
    }


def main():
    themes_dir, specs = Path(sys.argv[1]), json.loads(sys.argv[2])
    json.dump([theme(themes_dir / s["name"], s) for s in specs], sys.stdout)


main()
