#!/usr/bin/env python3
"""Report package version changes between two flake.lock files.

One representative host per platform is evaluated under both lock files, and
nothing is built. The derivation graph is walked down from each host's root through unversioned configuration glue (etc, units, home
files, profiles) and stops at the first versioned derivation. That derivation
is the package a host actually references, whether it arrived through
systemPackages, home.packages, a `programs.*.package` option, or a service
unit. Its own build dependencies are not reported.
"""

import argparse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import re
import subprocess
import sys

NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]
STORE = "/nix/store/"

# builtins.parseDrvName splits a name at the first dash followed by a digit.
VERSIONED = re.compile(r"^(.+?)-(\d.*)$")


def split_name(name):
    match = VERSIONED.match(name)
    return (match[1], match[2]) if match else (name, None)


def nix(*args):
    result = subprocess.run(
        [*NIX, *args], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        lines = result.stderr.strip().splitlines()
        raise RuntimeError(lines[-1] if lines else f"nix exited {result.returncode}")
    return result.stdout


# Representative hosts stand in for their platform; other hosts' private
# packages are not reported.
ROOTS = {
    "nixos": "nixosConfigurations.ellison.config.system.build.toplevel.drvPath",
    "darwin": "darwinConfigurations.golf.system.drvPath",
}


class Graph:
    """Derivation metadata, fetched lazily and shared across roots."""

    def __init__(self, show=None):
        self.show = show or self._nix_show
        self.nodes = {}

    @staticmethod
    def _nix_show(paths):
        return json.loads(nix("derivation", "show", *(STORE + p for p in paths)))

    def fetch(self, paths):
        missing = sorted(set(paths) - self.nodes.keys())
        if not missing:
            return
        shown = self.show(missing)
        # Nix 2.33 nests derivations and drops the store prefix from keys.
        shown = shown.get("derivations", shown)
        for key, drv in shown.items():
            inputs = drv.get("inputs", {}).get("drvs", drv.get("inputDrvs", {}))
            outputs = drv.get("outputs", {}).values()
            self.nodes[key.removeprefix(STORE)] = {
                "name": drv["name"],
                "inputs": [p.removeprefix(STORE) for p in inputs],
                "fixed": any("hash" in o or "hashAlgo" in o for o in outputs),
            }

    def packages(self, root):
        """Map pname to the set of versions referenced from root."""
        root = root.removeprefix(STORE)
        found = defaultdict(set)
        seen = {root}
        frontier = [root]
        while frontier:
            self.fetch(frontier)
            following = []
            for path in frontier:
                node = self.nodes[path]
                # Fetched sources and stdenv are how glue is built, not what
                # the host runs.
                if node["fixed"] or node["name"].startswith("stdenv-"):
                    continue
                pname, version = split_name(node["name"])
                if version is not None and path != root:
                    found[pname].add(version)
                    continue
                for dep in node["inputs"]:
                    if dep not in seen:
                        seen.add(dep)
                        following.append(dep)
            frontier = following
        return dict(found)


def changes(old, new):
    """Yield (kind, pname, removed versions, added versions)."""
    for pname in sorted(old.keys() | new.keys()):
        before, after = old.get(pname, set()), new.get(pname, set())
        if before == after:
            continue
        kind = "added" if not before else "removed" if not after else "updated"
        yield kind, pname, tuple(sorted(before - after)), tuple(sorted(after - before))


def group_changes(per_root):
    """Merge identical changes across roots: key -> sorted labels."""
    grouped = defaultdict(list)
    for label, (old, new) in sorted(per_root.items()):
        for change in changes(old, new):
            grouped[change].append(label)
    return grouped


def describe_input(node):
    locked = node.get("locked", {})
    ref = locked.get("rev", "")[:7] or locked.get("narHash", "")[7:14] or "?"
    stamp = locked.get("lastModified")
    if stamp is not None:
        day = datetime.fromtimestamp(stamp, timezone.utc).strftime("%Y-%m-%d")
        return ref, day
    return ref, None


def input_changes(old_lock, new_lock):
    """Yield (name, old description, new description) for direct inputs."""

    def direct(lock):
        nodes = lock["nodes"]
        inputs = nodes[lock["root"]].get("inputs", {})
        # A list is a `follows` path, which has no lock entry of its own.
        return {
            name: nodes[ref] for name, ref in inputs.items() if isinstance(ref, str)
        }

    old, new = direct(old_lock), direct(new_lock)
    for name in sorted(old.keys() | new.keys()):
        before, after = old.get(name), new.get(name)
        if before and after and before.get("locked") == after.get("locked"):
            continue
        yield (
            name,
            describe_input(before) if before else None,
            describe_input(after) if after else None,
        )


def table(rows, indent="  "):
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]) - 1)]
    return [
        indent + "  ".join(c.ljust(w) for c, w in zip(row, widths)) + "  " + row[-1]
        for row in rows
    ]


def report(inputs, grouped, failures):
    lines = []

    if inputs:
        lines.append("Inputs:")
        rows = []
        for name, before, after in inputs:
            refs = f"{before[0] if before else '(new)'} -> {after[0] if after else '(gone)'}"
            days = ""
            if before and after and before[1] and after[1]:
                days = f"({before[1]} -> {after[1]})"
            rows.append((name, refs, days))
        lines += [line.rstrip() for line in table(rows)]
        lines.append("")

    sections = {"updated": "Updated:", "added": "Added:", "removed": "Removed:"}
    for kind, title in sections.items():
        rows = []
        for (k, pname, removed, added), group in sorted(grouped.items()):
            if k != kind:
                continue
            if kind == "updated":
                versions = f"{', '.join(removed)} -> {', '.join(added)}"
            else:
                versions = ", ".join(added or removed)
            rows.append((pname, versions, ", ".join(group)))
        if rows:
            lines.append(title)
            lines += table(rows)
            lines.append("")

    if not grouped:
        lines += ["No package version changes.", ""]

    if failures:
        lines.append("Not compared:")
        lines += [f"  {label} ({side} lock): {err}" for label, side, err in failures]
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("old_lock", help="flake.lock to compare against")
    parser.add_argument("flake", nargs="?", default=".", help="flake to evaluate")
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=1,
        help="evaluations run in parallel (each takes a few GiB)",
    )
    args = parser.parse_args(argv)

    with open(args.old_lock, encoding="utf-8") as f:
        old_lock = json.load(f)
    with open(f"{args.flake}/flake.lock", encoding="utf-8") as f:
        new_lock = json.load(f)

    sides = {"old": ["--reference-lock-file", args.old_lock], "new": []}

    def instantiate(job):
        label, side = job
        print(f"evaluating {label} ({side} lock)", file=sys.stderr)
        try:
            out = nix("eval", "--raw", *sides[side], f"{args.flake}#{ROOTS[label]}")
            return label, side, out.strip(), None
        except RuntimeError as err:
            return label, side, None, str(err)

    jobs = [(label, side) for label in ROOTS for side in sides]
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(instantiate, jobs))

    drvs = defaultdict(dict)
    failures = []
    for label, side, drv, err in results:
        if err:
            failures.append((label, side, err))
        else:
            drvs[label][side] = drv

    graph = Graph()
    per_root = {}
    for label, sides_drv in sorted(drvs.items()):
        if len(sides_drv) == 2:
            print(f"walking {label}", file=sys.stderr)
            per_root[label] = (
                graph.packages(sides_drv["old"]),
                graph.packages(sides_drv["new"]),
            )

    sys.stdout.write(
        report(
            list(input_changes(old_lock, new_lock)),
            group_changes(per_root),
            failures,
        )
    )


if __name__ == "__main__":
    main()
