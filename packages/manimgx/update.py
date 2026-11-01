"""Pin ManimGX's wheels and the font wheels it requires, from PyPI."""

import re
import sys

from updater import UpdateError
from updater.kinds import pypi_release
from updater.package import Package
from updater.pins import hex_to_sri, read_sources, write_sources

FONTS = ("manimgx-fonts", "manimgx-fonts-cjk")


def wheel_hash(release: dict, filename: str) -> str:
    for file in release["urls"]:
        if file["filename"] == filename:
            return hex_to_sri(file["digests"]["sha256"])
    raise UpdateError(f"PyPI lists no {filename}")


def required_version(release: dict, name: str) -> str:
    for requirement in release["info"]["requires_dist"] or []:
        match = re.match(rf"{re.escape(name)}==([^;\s]+)", requirement)
        if match:
            return match[1]
    raise UpdateError(f"manimgx does not pin {name}")


def main() -> None:
    pkg = Package.from_env()
    version = pypi_release("manimgx")["info"]["version"]
    release = pypi_release("manimgx", version)

    hashes = {
        system: wheel_hash(release, f"manimgx-{version}-cp313-abi3-{platform}.whl")
        for system, platform in sorted(pkg.updater["settings"]["platforms"].items())
    }
    fonts = {}
    for name in FONTS:
        font_version = required_version(release, name)
        wheel = f"{name.replace('-', '_')}-{font_version}-py3-none-any.whl"
        fonts[name] = {
            "version": font_version,
            "hash": wheel_hash(pypi_release(name, font_version), wheel),
        }

    # The repository checkout is a fetch of the release tag; the driver
    # re-pins it once the version moves.
    repo = read_sources(pkg.dir)["repo"]
    write_sources(
        pkg.dir, {"version": version, "hashes": hashes, "fonts": fonts, "repo": repo}
    )


if __name__ == "__main__":
    try:
        main()
    except UpdateError as error:
        sys.exit(f"manimgx: {error}")
