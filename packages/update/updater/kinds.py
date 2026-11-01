"""The update kinds a ``passthru.updater`` names, cheapest first."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Any

from . import UpdateError, net, nix
from .pins import dig, hex_to_sri, interpolate, read_sources, strip_v, write_sources

if TYPE_CHECKING:
    from collections.abc import Callable

    from .package import Package


def latest_version(source: dict[str, Any]) -> str:
    """Resolve a ``versionSource`` to the upstream's current version."""
    kind = source["type"]
    if kind == "github":
        url = f"https://api.github.com/repos/{source['owner']}/{source['repo']}/releases/latest"
        return strip_v(net.fetch_json(url)["tag_name"])
    if kind == "npm":
        return npm_version(source["package"], source.get("tag", "latest"))
    if kind == "pypi":
        return pypi_release(source["package"])["info"]["version"]
    if kind == "json":
        return str(dig(net.fetch_json(source["url"]), source["path"]))
    raise UpdateError(f"unknown versionSource type {kind!r}")


def npm_version(package: str, tag: str = "latest") -> str:
    tags = net.fetch_json(f"https://registry.npmjs.org/-/package/{package}/dist-tags")
    if tag not in tags:
        raise UpdateError(f"npm package {package} has no dist-tag {tag!r}")
    return tags[tag]


def pypi_release(package: str, version: str | None = None) -> dict[str, Any]:
    path = f"{package}/{version}" if version else package
    return net.fetch_json(f"https://pypi.org/pypi/{path}/json")


def _pins_current(pkg: Package, latest: str, platforms: dict[str, str]) -> bool:
    sources = read_sources(pkg.dir)
    return sources.get("version") == latest and set(sources.get("hashes", {})) == set(platforms)


def nix_update(pkg: Package, config: dict[str, Any]) -> None:
    nix.run(["nix-update", "--flake", pkg.name, *config.get("args", [])], cwd=pkg.root)


def npm(pkg: Package, config: dict[str, Any]) -> None:
    """Bump an npm registry tarball and regenerate its vendored lockfile.

    The tarball carries no lockfile, and the lockfile must match package.json
    after the package's own ``postPatch`` filter, so the lock is generated
    here from the filtered package.json rather than by nix-update.
    """
    latest = npm_version(config.get("package", pkg.pname), config.get("distTag", "latest"))
    if latest == pkg.version:
        return
    nix.run(["nix-update", "--flake", pkg.name, "--version", latest, "--src-only"], cwd=pkg.root)
    tarball = nix.build(pkg.attr("src"))
    generate_lockfile(Path(tarball), config["lockfileFilter"], pkg.dir / "package-lock.json")
    pkg.refresh_hash("npmDeps")


def generate_lockfile(tarball: Path, jq_filter: str, dest: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        with tarfile.open(tarball) as archive:
            archive.extractall(work / "src", filter="data")
        (source,) = (work / "src").iterdir()
        manifest = source / "package.json"
        filtered = nix.run(["jq", jq_filter, str(manifest)], capture=True).stdout
        manifest.write_text(filtered)
        env = dict(
            os.environ,
            HOME=str(work),
            npm_config_cache=str(work / "cache"),
            npm_config_update_notifier="false",
        )
        nix.run(
            [
                "npm",
                "install",
                "--package-lock-only",
                "--ignore-scripts",
                "--no-audit",
                "--no-fund",
            ],
            cwd=source,
            env=env,
        )
        shutil.copyfile(source / "package-lock.json", dest)


def platform_binaries(pkg: Package, config: dict[str, Any]) -> None:
    """Pin one prebuilt archive per platform, downloading each to hash it."""
    latest = latest_version(config["versionSource"])
    platforms: dict[str, str] = config["platforms"]
    if _pins_current(pkg, latest, platforms):
        return
    hashes = {}
    for system, token in sorted(platforms.items()):
        url = interpolate(config["urlTemplate"], version=latest, platform=token)
        hashes[system], _ = nix.prefetch(url)
    write_sources(pkg.dir, {"version": latest, "hashes": hashes})


def manifest_checksums(pkg: Package, config: dict[str, Any]) -> None:
    """Pin per-platform binaries from the checksums in the vendor's manifest."""
    latest = latest_version(config["versionSource"])
    platforms: dict[str, str] = config["platforms"]
    if _pins_current(pkg, latest, platforms):
        return
    manifest = net.fetch_json(interpolate(config["manifestUrl"], version=latest))
    hashes = {
        system: hex_to_sri(dig(manifest, interpolate(config["checksumPath"], platform=token)))
        for system, token in sorted(platforms.items())
    }
    write_sources(pkg.dir, {"version": latest, "hashes": hashes})


def script(pkg: Package, _config: dict[str, Any]) -> None:
    path = pkg.dir / "update.py"
    if not path.exists():
        raise UpdateError(f"{pkg.name}: kind 'script' needs {path}")
    env = dict(
        os.environ,
        UPDATE_PACKAGE=pkg.name,
        UPDATE_SYSTEM=pkg.system,
        UPDATE_ROOT=str(pkg.root),
        UPDATE_VERSION=pkg.version,
        UPDATE_CONFIG=json.dumps(pkg.updater),
    )
    print(f"+ {path}", file=sys.stderr, flush=True)
    result = subprocess.run([sys.executable, str(path)], cwd=pkg.root, env=env, check=False)
    if result.returncode != 0:
        raise UpdateError(f"{path} exited {result.returncode}")


KINDS: dict[str, Callable[[Package, dict[str, Any]], None]] = {
    "nix-update": nix_update,
    "npm": npm,
    "platform-binaries": platform_binaries,
    "manifest-checksums": manifest_checksums,
    "script": script,
}


def run_kind(pkg: Package) -> None:
    kind = pkg.updater["kind"]
    if kind not in KINDS:
        raise UpdateError(f"{pkg.name}: unknown updater kind {kind!r}")
    KINDS[kind](pkg, pkg.updater)
