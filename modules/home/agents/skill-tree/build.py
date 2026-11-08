"""Assemble the skill tree agents see, failing on any inconsistency.

Usage: build.py SPEC OUT, where SPEC is the JSON build.nix
writes from dotfiles.agents.skills.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

spec = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
errors = []

# name -> (source directory, origin); origin is a package path or "local".
sources = {}
from_packages = set()


def add(name, source, origin):
    if name in sources:
        errors.append(f"skill {name} comes from both {sources[name][1]} and {origin}")
        return
    sources[name] = (Path(source), origin)


for package in spec["packages"]:
    root = Path(package) / "share/skills"
    entries = sorted(root.iterdir()) if root.is_dir() else []
    if not entries:
        errors.append(f"{package} is listed in packages but has no skills in share/skills")
    for entry in entries:
        if not entry.is_dir():
            errors.append(f"{entry} is not a skill directory")
            continue
        add(entry.name, entry, package)
        from_packages.add(entry.name)

for name, source in spec["local"].items():
    add(name, source, "local")

patches = {}
for name, override in spec["override"].items():
    modes = [m for m in ("patches", "replace", "ignore") if override[m]]
    if len(modes) != 1:
        errors.append(
            f"override.{name} sets {modes or 'nothing'}; "
            "set exactly one of patches, replace or ignore"
        )
        continue
    if name not in from_packages:
        errors.append(f"override.{name} names no skill a listed package provides")
        continue
    if override["ignore"]:
        del sources[name]
    elif override["replace"]:
        sources[name] = (Path(override["replace"]), "override")
    else:
        patches[name] = override["patches"]

# What agents read as docs must not also reach them as a skill.
for doc, path in spec["docs"].items():
    for name, (source, _) in sorted(sources.items()):
        skill = str(source)
        if (
            path == skill
            or skill.startswith(path.rstrip("/") + "/")
            or path.startswith(skill + "/")
        ):
            errors.append(f"docs.{doc} reads skill {name}, which agents also see")

# Claude Code keeps the skills it downloads from the account there.
if "synced" in sources:
    errors.append("a skill is named synced, which Claude Code reserves in ~/.claude/skills")

skills = out / "skills"
skills.mkdir(parents=True)
for name, (source, origin) in sorted(sources.items()):
    target = skills / name
    shutil.copytree(source, target, symlinks=False)
    # Store copies are read-only; patching and the next copy need write access.
    for path in [target, *target.rglob("*")]:
        path.chmod(path.stat().st_mode | 0o200)

    for patch in patches.get(name, []):
        result = subprocess.run(
            [
                "patch",
                "-p1",
                "--fuzz=0",
                "--forward",
                "--no-backup-if-mismatch",
                "-d",
                str(target),
                "-i",
                patch,
            ],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            errors.append(
                f"{patch} does not apply to skill {name}:\n{result.stdout}{result.stderr}"
            )

    manifest = target / "SKILL.md"
    if not manifest.is_file():
        errors.append(f"skill {name} ({origin}) has no SKILL.md")
        continue
    text = manifest.read_text()
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---" or "---" not in (line.strip() for line in lines[1:]):
        errors.append(f"skill {name} ({origin}): SKILL.md has no YAML frontmatter")
        continue
    end = next(i for i, line in enumerate(lines[1:], 1) if line.strip() == "---")
    try:
        meta = yaml.safe_load("\n".join(lines[1:end]))
    except yaml.YAMLError as error:
        errors.append(f"skill {name} ({origin}): SKILL.md frontmatter is not YAML: {error}")
        continue
    if not isinstance(meta, dict):
        errors.append(f"skill {name} ({origin}): SKILL.md frontmatter is not a mapping")
        continue
    if meta.get("name") != name:
        errors.append(
            f"skill {name} ({origin}): SKILL.md names it {meta.get('name')!r}, not its directory"
        )
    description = meta.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append(f"skill {name} ({origin}): SKILL.md has no description")

# Home Manager links a recursive source file by file but copies the links it
# finds there as they are, so a root linked from here holds one link per
# skill directory.
links = out / "links"
links.mkdir()
for name in sorted(sources):
    (links / name).symlink_to(skills / name)

docs = out / "docs"
docs.mkdir()
for name, path in spec["docs"].items():
    (docs / name).symlink_to(path)

(out / "names").write_text("".join(f"{name}\n" for name in sorted(sources)))

if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    sys.exit(1)
