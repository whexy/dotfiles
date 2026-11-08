"""Bring along what the skills a repository published link to outside themselves.

Usage: skill-repo-links.py SRC SHARE, where SRC is the repository and
SHARE/skills holds the skills the `skills` CLI installed from it.

The CLI copies each skill directory alone, but a skill may link by relative
path to a file beside the skills/ folder it came from, as pstack's do to
../../docs/harness/claude-code.md. Each such target is copied to SHARE at
the same place relative to skills/, and the link rewritten to that absolute
path. Agents read a skill through its own skills root, where some resolve
`..` lexically and others through the link into the skill tree, so only an
absolute path names the same file both ways.
"""

import os
import re
import shutil
import sys
from pathlib import Path

src = Path(sys.argv[1])
share = Path(sys.argv[2])
skills = share / "skills"
errors = []

INLINE = re.compile(r"(\]\(\s*<?)([^)\s<>]+)")
REFERENCE = re.compile(r"^(\s*\[[^\]]+\]:\s*<?)([^\s<>]+)", re.MULTILINE)


def relative(target):
    """The path a link target names relative to its file, or None."""
    if target.startswith(("#", "/", "~")) or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
        return None
    path = target.split("#", 1)[0].split("?", 1)[0]
    return path or None


def tree_files(root):
    if root.is_file():
        return {Path(): root.read_bytes()}
    return {p.relative_to(root): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


def same(a, b):
    return a.is_dir() == b.is_dir() and tree_files(a) == tree_files(b)


# The CLI records no source path, so a skill came from whichever directory of
# that name holds exactly what it installed.
published = {}
for directory, _, files in os.walk(src):
    if "SKILL.md" in files:
        published.setdefault(Path(directory).name, []).append(Path(directory))

copied = set()


def bring(base, rel):
    """Copy base/rel to share/rel with what its Markdown links to beside it."""
    if rel in copied:
        return
    copied.add(rel)
    origin, dest = base / rel, share / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if origin.is_dir():
        shutil.copytree(origin, dest, symlinks=False)
    else:
        shutil.copyfile(origin, dest)
    docs = [origin] if origin.is_file() else sorted(origin.rglob("*.md"))
    for doc in docs:
        if doc.suffix != ".md":
            continue
        text = doc.read_text()
        for match in [*INLINE.finditer(text), *REFERENCE.finditer(text)]:
            path = relative(match.group(2))
            if path is None:
                continue
            nested = Path(os.path.normpath(doc.parent.relative_to(base) / path))
            # A doc's links to skills are the skill set's concern, not a doc's.
            if nested.parts[0] in ("..", "skills") or not (base / nested).exists():
                continue
            bring(base, nested)


for skill in sorted(skills.iterdir()):
    origins = [d for d in published.get(skill.name, []) if same(d, skill)]
    if not origins:
        errors.append(f"skill {skill.name} matches no directory in {src}")
        continue
    for doc in sorted(skill.rglob("*.md")):
        text = doc.read_text()

        def rewrite(match, skill=skill, doc=doc, origins=origins):
            target = match.group(2)
            path = relative(target)
            if path is None:
                return match.group(0)
            # Relative to the folder holding skills/.
            rel = Path(
                os.path.normpath(Path("skills") / skill.name / doc.parent.relative_to(skill) / path)
            )
            if rel.parts[0] == "skills":
                return match.group(0)
            if rel.parts[0] == "..":
                errors.append(f"skill {skill.name}: {target} leaves the folder holding skills/")
                return match.group(0)
            found = [d.parent.parent for d in origins if (d.parent.parent / rel).exists()]
            if not found:
                errors.append(f"skill {skill.name}: {target} is not in {src}")
                return match.group(0)
            if any(not same(found[0] / rel, base / rel) for base in found[1:]):
                errors.append(
                    f"skill {skill.name}: {target} differs between the copies it may come from: "
                    + ", ".join(str(base / rel) for base in found)
                )
                return match.group(0)
            bring(found[0], rel)
            fragment = target[len(target.split("#", 1)[0]) :]
            return match.group(1) + str(share / rel) + fragment

        new = REFERENCE.sub(rewrite, INLINE.sub(rewrite, text))
        if new != text:
            doc.write_text(new)

if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    sys.exit(1)
