"""Bump HyperFrames from npm, and its vendored GSAP to the templates' version."""

import re
import sys
import tarfile
from collections import Counter

from updater import UpdateError, kinds, nix
from updater.package import Package
from updater.pins import replace_once

GSAP = re.compile(rb"gsap@(\d+\.\d+\.\d+)/dist/gsap\.min\.js")


def templates_gsap(tarball: str) -> str:
    """The GSAP version most of the init templates load."""
    seen: Counter[str] = Counter()
    with tarfile.open(tarball) as archive:
        for member in archive.getmembers():
            if member.isfile() and "/dist/templates/" in member.name:
                file = archive.extractfile(member)
                if file is not None:
                    seen.update(m.decode() for m in GSAP.findall(file.read()))
    if not seen:
        raise UpdateError("no template names a GSAP version")
    return seen.most_common(1)[0][0]


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


if __name__ == "__main__":
    try:
        main()
    except UpdateError as error:
        sys.exit(f"hyperframes: {error}")
