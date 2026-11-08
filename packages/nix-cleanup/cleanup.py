"""Thin Nix profile history before collecting unreferenced store paths."""

import argparse
import os
import pwd
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass(frozen=True)
class Generation:
    number: int
    created: datetime
    current: bool = False


def retained(generations):
    ordered = sorted(generations, key=lambda g: (g.created, g.number), reverse=True)
    keep = {g.number for g in ordered[:5]}
    weeks, months = set(), set()
    for generation in ordered:
        week = generation.created.isocalendar()[:2]
        month = (generation.created.year, generation.created.month)
        if week not in weeks and len(weeks) < 4:
            weeks.add(week)
            keep.add(generation.number)
        if month not in months and len(months) < 3:
            months.add(month)
            keep.add(generation.number)
        if generation.current:
            keep.add(generation.number)
    return keep


def parse_generations(output):
    generations = []
    for line in output.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(
            r"\s*(\d+)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(\s+\(current\))?\s*",
            line,
        )
        if match is None:
            raise ValueError(f"Unrecognised generation listing: {line!r}")
        generations.append(
            Generation(int(match[1]), datetime.fromisoformat(match[2]), bool(match[3]))
        )
    if generations and sum(g.current for g in generations) != 1:
        raise ValueError("Expected exactly one current generation")
    return generations


def profiles_in(directory):
    if not directory.is_dir():
        return set()
    profiles = set()
    for entry in directory.iterdir():
        match = re.fullmatch(r"(.+)-\d+-link", entry.name)
        if match and entry.is_symlink():
            profile = directory / match[1]
            # An abandoned profile has no current pointer and is left alone.
            if profile.is_symlink():
                profiles.add(profile)
    return profiles


def discover_profiles(system, profiles_root=Path("/nix/var/nix/profiles"), on_error=None):
    def report(directory, error):
        if on_error is None:
            raise error
        on_error(directory, error)

    def scan(directory):
        try:
            return profiles_in(directory)
        except OSError as error:
            report(directory, error)
            return set()

    home = Path.home()
    state = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    own_profiles = profiles_root / "per-user" / pwd.getpwuid(os.geteuid()).pw_name
    directories = {
        state / "nix/profiles",
        home / ".local/state/nix/profiles",
        own_profiles,
    }
    profiles = set()
    legacy = home / ".nix-profile"
    try:
        if legacy.is_symlink():
            if legacy in scan(home):
                profiles.add(legacy)
            # pathlib has no abspath: resolve() also follows the profile's own
            # links, and absolute() keeps `..`.
            target = Path(os.path.abspath(legacy.parent / legacy.readlink()))  # noqa: PTH100
            # The multi-user installer gives root the global default profile, even
            # when only a standalone Home Manager user job manages that host.
            root_default = os.geteuid() == 0 and target == profiles_root / "default"
            if (
                target.is_relative_to(home) or target.is_relative_to(own_profiles) or root_default
            ) and target in scan(target.parent):
                profiles.add(target)
    except OSError as error:
        report(legacy, error)
    if system:
        directories.add(profiles_root)
        per_user = profiles_root / "per-user"
        try:
            if per_user.is_dir():
                directories.update(p for p in per_user.iterdir() if p.is_dir())
        except OSError as error:
            report(per_user, error)
    return sorted(profiles | set().union(*(scan(d) for d in directories)))


def prune(profile, dry_run):
    output = subprocess.check_output(
        ["nix-env", "--profile", str(profile), "--list-generations"],
        text=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    generations = parse_generations(output)
    keep = retained(generations)
    remove = [str(g.number) for g in generations if g.number not in keep]
    print(f"{profile}: keep {sorted(keep)}, remove {remove}", flush=True)
    if remove and not dry_run:
        # Nix locks the profile and rejects deletion of its current generation,
        # including one switched to since the listing above.
        subprocess.run(
            ["nix-env", "--profile", str(profile), "--delete-generations", *remove],
            check=True,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--system", action="store_true", help="also prune global profiles")
    parser.add_argument("--dry-run", action="store_true", help="only print deletions and GC")
    args = parser.parse_args()
    if args.system and os.geteuid() != 0:
        parser.error("--system requires root")
    failed = False

    def report_failure(profile, error):
        nonlocal failed
        print(f"{profile}: cleanup failed: {error}", file=sys.stderr, flush=True)
        failed = True

    for profile in discover_profiles(args.system, on_error=report_failure):
        try:
            prune(profile, args.dry_run)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            report_failure(profile, error)
    print(
        "Would run nix-collect-garbage" if args.dry_run else "Running nix-collect-garbage",
        flush=True,
    )
    if not args.dry_run:
        subprocess.run(["nix-collect-garbage"], check=True)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
