"""``nix run .#update [-- names...] [--list] [--commit]``."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import traceback
from pathlib import Path
from typing import Any

from . import UpdateError, nix
from .kinds import run_kind
from .package import Package
from .pins import compare_versions

# Packages are discovered on one system so the list does not depend on the
# machine; each update then evaluates and builds on the machine's own system.
DISCOVERY_SYSTEM = "x86_64-linux"
FLAKE_SYSTEMS = ("x86_64-linux", "aarch64-linux", "aarch64-darwin")

# A package that fails to evaluate is reported, not skipped, so a broken
# updater config fails the run.
DISCOVER = """
pkgs: builtins.listToAttrs (map (name:
  let
    pkg = pkgs.${name};
    found = builtins.tryEval (
      let updater = pkg.passthru.updater or null; in
      if updater == null then null
      else builtins.deepSeq updater {
        inherit updater;
        inherit (pkg) version;
        pname = pkg.pname or name;
        changelog = pkg.meta.changelog or null;
      });
  in { inherit name; value = if found.success then found.value else { error = true; }; }
) (builtins.attrNames pkgs))
"""

NAME = re.compile(r"[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*")

Snapshot = dict[str, bytes]


def snapshot(directory: Path) -> Snapshot:
    return {
        str(path.relative_to(directory)): path.read_bytes()
        for path in sorted(directory.rglob("*"))
        if path.is_file()
    }


def restore(directory: Path, saved: Snapshot) -> None:
    for path in directory.rglob("*"):
        if path.is_file() and str(path.relative_to(directory)) not in saved:
            path.unlink()
    for relative, content in saved.items():
        (directory / relative).write_bytes(content)


def changed_files(directory: Path, saved: Snapshot) -> list[Path]:
    now = snapshot(directory)
    names = {n for n in now.keys() | saved.keys() if now.get(n) != saved.get(n)}
    return [directory / n for n in sorted(names)]


def commit_message(name: str, old: str, new: str, changelog: str | None) -> list[str]:
    title = f"chore({name}): {old} -> {new}" if old != new else f"chore({name}): refresh {new} pins"
    return [title] + ([f"Changelog: {changelog}"] if changelog else [])


def discover(root: Path) -> dict[str, dict[str, Any]]:
    found = nix.eval_json(f"{root}#packages.{DISCOVERY_SYSTEM}", apply=DISCOVER)
    return {name: info for name, info in sorted(found.items()) if info is not None}


def evaluation_error(root: Path, name: str) -> str:
    result = nix.run(
        ["nix", "eval", "--json", f"{root}#packages.{DISCOVERY_SYSTEM}.{name}.passthru.updater"],
        capture=True,
        check=False,
    )
    return result.stderr.strip()[-2000:] or "evaluation failed"


def check_targets(pkg: Package, targets: list[str]) -> None:
    """Build each target on this system, and evaluate it on the others."""
    pairs = [{"system": s, "path": t.split(".")} for t in targets for s in FLAKE_SYSTEMS]
    apply = f"""
    ps: map (pair:
      let p = builtins.foldl' (a: n: if a == null then null else a.${{n}} or null)
        ps.${{pair.system}} pair.path;
      in if p != null && builtins.elem pair.system (p.meta.platforms or [ pair.system ])
         then p.drvPath else null
    ) (builtins.fromJSON {json.dumps(json.dumps(pairs))})
    """
    drvs = nix.eval_json(f"{pkg.root}#packages", apply=apply)
    for pair, drv in zip(pairs, drvs, strict=True):
        target = ".".join(pair["path"])
        if pair["system"] == pkg.system and drv is not None:
            nix.run(["nix", "build", "--no-link", f"{pkg.root}#packages.{pkg.system}.{target}"])
        elif drv is not None:
            print(f"{target} evaluates on {pair['system']}", file=sys.stderr)


def update(pkg: Package, *, commit: bool) -> str | None:
    """Update one package; return its new version, or None when unchanged."""
    if commit and nix.git("status", "--porcelain", "--", str(pkg.dir)):
        raise UpdateError(f"{pkg.dir} has uncommitted changes")
    saved = snapshot(pkg.dir)
    outside = nix.git("status", "--porcelain")
    try:
        run_kind(pkg)
        changed = changed_files(pkg.dir, saved)
        if not changed:
            return None
        for attr in pkg.updater.get("followBranch", []):
            pkg.follow_branch(attr)
        for attr in pkg.updater.get("subpackages", []):
            pkg.refresh_hash(attr)
        changed = changed_files(pkg.dir, saved)
        nix.run(["treefmt", *[str(p) for p in changed if p.exists()]], cwd=pkg.root)
        if not changed_files(pkg.dir, saved):
            return None
        if _outside_changed(pkg, outside):
            raise UpdateError("the updater changed files outside its package")
        info = nix.eval_json(
            pkg.attr(), apply="p: { inherit (p) version; changelog = p.meta.changelog or null; }"
        )
        new = info["version"]
        if compare_versions(new, pkg.version) < 0 and not pkg.updater.get("allowDowngrade"):
            raise UpdateError(f"refusing to downgrade {pkg.version} -> {new}")
        check_targets(pkg, [pkg.name, *pkg.updater.get("alsoBuild", [])])
        if commit:
            nix.git("add", "-A", "--", str(pkg.dir))
            message = commit_message(pkg.name, pkg.version, new, info["changelog"])
            nix.git("commit", "--quiet", *[a for line in message for a in ("-m", line)])
    except BaseException:
        restore(pkg.dir, saved)
        raise
    return new


def _outside_changed(pkg: Package, before: str) -> bool:
    prefix = str(pkg.dir.relative_to(pkg.root)) + "/"
    after = nix.git("status", "--porcelain")

    def outside(status: str) -> set[str]:
        return {line for line in status.splitlines() if not line[3:].startswith(prefix)}

    return outside(after) != outside(before)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="update", description=__doc__)
    parser.add_argument("names", nargs="*", help="packages to update (default: all)")
    parser.add_argument("--list", action="store_true", help="list updatable packages")
    parser.add_argument("--commit", action="store_true", help="commit each update")
    args = parser.parse_args(argv)

    root = Path(nix.git("rev-parse", "--show-toplevel").strip())
    os.chdir(root)
    # Child nix calls, nix-update's included, use the flake's substituters.
    os.environ["NIX_CONFIG"] = os.environ.get("NIX_CONFIG", "") + "\naccept-flake-config = true\n"

    for name in args.names:
        if not NAME.fullmatch(name):
            parser.error(f"not a package name: {name!r}")
    found = discover(root)
    unknown = [n for n in args.names if n not in found]
    if unknown:
        parser.error(f"no updatable package named {', '.join(unknown)}")
    selected = args.names or list(found)

    failed: dict[str, str] = {}
    for name in selected:
        if found[name].get("error"):
            failed[name] = evaluation_error(root, name)
    if args.list:
        for name in selected:
            if name not in failed:
                info = found[name]
                print(f"{name}  {info['version']}  {info['updater']['kind']}")
        for name, error in failed.items():
            print(f"{name}: {error}", file=sys.stderr)
        return 1 if failed else 0

    system = nix.current_system()
    updated: dict[str, str] = {}
    for name in selected:
        if name in failed:
            continue
        info = found[name]
        pkg = Package(
            name=name,
            version=info["version"],
            system=system,
            root=root,
            pname=info["pname"],
            changelog=info["changelog"],
            updater=info["updater"],
        )
        print(f"=== {name} {pkg.version}", file=sys.stderr, flush=True)
        try:
            new = update(pkg, commit=args.commit)
        except Exception as error:  # one package must not stop the rest
            if not isinstance(error, UpdateError):
                traceback.print_exc()
            failed[name] = str(error) or type(error).__name__
            print(f"FAIL {name}: {failed[name]}", file=sys.stderr, flush=True)
            continue
        if new is None:
            print(f"OK   {name}: up to date", file=sys.stderr, flush=True)
        else:
            updated[name] = f"{pkg.version} -> {new}"
            print(f"OK   {name}: {updated[name]}", file=sys.stderr, flush=True)

    print("\nSummary", file=sys.stderr)
    for name, change in updated.items():
        print(f"  updated  {name}  {change}", file=sys.stderr)
    for name, error in failed.items():
        print(f"  failed   {name}  {error.splitlines()[0] if error else ''}", file=sys.stderr)
    if not updated and not failed:
        print("  every package is up to date", file=sys.stderr)
    return 1 if failed else 0
