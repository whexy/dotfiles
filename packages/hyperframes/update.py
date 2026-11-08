"""Bump HyperFrames from npm, and its vendored GSAP to the templates' version."""

import functools
import re
import tarfile

from updater import UpdateError, kinds, nix
from updater.package import Package
from updater.pins import compare_versions, replace_once

GSAP = re.compile(rb"gsap@(\d+\.\d+\.\d+)/dist/gsap\.min\.js")


def templates_gsap(tarball: str) -> str:
    """The newest GSAP version any init template loads.

    Templates move to a new GSAP one at a time, and GSAP keeps its API within
    a major version, so the newest one serves compositions from every
    template.
    """
    seen: set[str] = set()
    with tarfile.open(tarball) as archive:
        for member in archive.getmembers():
            if member.isfile() and "/dist/templates/" in member.name:
                file = archive.extractfile(member)
                if file is not None:
                    seen.update(m.decode() for m in GSAP.findall(file.read()))
    if not seen:
        raise UpdateError("no template names a GSAP version")
    majors = {version.split(".")[0] for version in seen}
    if len(majors) > 1:
        raise UpdateError(f"the templates load GSAP {', '.join(sorted(seen))}, across majors")
    return max(seen, key=functools.cmp_to_key(compare_versions))


def main() -> None:
    pkg = Package.from_env()
    kinds.npm(pkg, pkg.updater["settings"])

    url = nix.eval_raw(pkg.attr("gsapTarball.url"))
    current = re.search(r"gsap-(\d+\.\d+\.\d+)\.tgz$", url)
    if current is None:
        raise UpdateError(f"cannot read the GSAP version from {url}")
    wanted = templates_gsap(nix.build(pkg.attr("src")))
    if wanted != current[1]:
        replace_once(pkg.dir / "default.nix", f"gsap-{current[1]}.tgz", f"gsap-{wanted}.tgz")
        pkg.refresh_hash("gsapTarball")
