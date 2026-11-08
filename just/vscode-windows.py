"""Merge vscode-neovim's WSL settings into a VS Code settings.json.

VS Code reads settings.json as JSON with comments and trailing commas. This
writes plain JSON back, so it refuses a file with comments instead of
dropping them.
"""

import json
import os
import sys


def strip_jsonc(text):
    """Return (text without comments and trailing commas, had_comments)."""
    out = []
    had_comments = False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i : j + 1])
            i = j + 1
        elif text.startswith("//", i):
            had_comments = True
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            had_comments = True
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif c == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j >= n or text[j] not in "}]":
                out.append(c)
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out), had_comments


def main():
    path, nvim, distro = sys.argv[1:]
    wanted = {
        "vscode-neovim.useWSL": True,
        "vscode-neovim.wslDistribution": distro,
        "vscode-neovim.neovimExecutablePaths.linux": nvim,
    }

    try:
        with open(path, encoding="utf-8-sig") as f:
            original = f.read()
    except FileNotFoundError:
        original = ""

    text, had_comments = strip_jsonc(original)
    if had_comments:
        sys.exit(
            f"error: {path} has comments, which this would drop; "
            "remove them or add these settings by hand:\n" + json.dumps(wanted, indent=4)
        )
    settings = json.loads(text) if text.strip() else {}

    if all(settings.get(k) == v for k, v in wanted.items()):
        print(f"{path} already points vscode-neovim at {nvim}")
        return

    settings.update(wanted)
    if original:
        with open(path + ".bak", "w", encoding="utf-8") as f:
            f.write(original)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=4, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
    print(f"Updated {path}; reload VS Code windows to restart vscode-neovim.")


main()
