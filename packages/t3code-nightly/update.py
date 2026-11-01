"""Pin the npm `nightly` dist-tag of T3 Code, its desktop app and its browser."""

import re
import sys
import tarfile

from updater import UpdateError, net, nix
from updater.kinds import npm_version
from updater.package import Package
from updater.pins import b64_to_sri, hex_to_sri, write_sources


def checksums(sums: str, version: str) -> dict[str, str]:
    """The CLI archives' hashes, from the release's SHA256SUMS."""
    listed = dict(reversed(line.split()) for line in sums.splitlines() if line.strip())
    hashes = {}
    for platform in ("darwin-arm64", "linux-arm64", "linux-x64"):
        archive = f"t3-{version}-{platform}.tar.gz"
        if archive not in listed:
            raise UpdateError(f"{archive} is not listed in SHA256SUMS")
        hashes[platform] = hex_to_sri(listed[archive])
    return hashes


def appimage_hash(manifest: str, file: str) -> str:
    """An AppImage's hash, from an electron-updater manifest."""
    url = None
    for line in manifest.splitlines():
        fields = line.split()
        if fields[:2] == ["-", "url:"] and len(fields) > 2:
            url = fields[2]
        elif fields[:1] == ["sha512:"] and len(fields) > 1 and url == file:
            return b64_to_sri("sha512", fields[1])
    raise UpdateError(f"no sha512 for {file} in the desktop manifest")


START = re.compile(rb"^//(#region)? src/preview/PreviewBrowser\.ts$")
END = re.compile(rb"chromePlatform = ")
PLATFORM = re.compile(rb'^\t\t"?([a-z0-9-]+)"?: \{')


def browser_pins(executable: bytes) -> dict[str, str]:
    """The Chrome for Testing pin in the server source embedded in `t3`.

    Builds since 0.1.3-nightly.20261026 open each bundled module with
    `// <path>` instead of `//#region <path>`.
    """
    pins: dict[str, str] = {}
    inside = False
    platform = None
    for line in executable.split(b"\n"):
        if not inside:
            inside = START.search(line) is not None
            if not inside:
                continue
        if b'VERSION = "' in line and "version" not in pins:
            pins["version"] = re.search(rb'"([^"]+)"', line)[1].decode()
        if match := PLATFORM.search(line):
            platform = match[1].decode()
        if platform and b"sha256:" in line:
            digest = re.search(rb'"([0-9a-f]+)"', line)
            if digest:
                pins.setdefault(platform, digest[1].decode())
            platform = None
        if END.search(line):
            inside = False
    missing = {"version", "linux64", "linux-arm64"} - set(pins)
    if missing:
        raise UpdateError(f"no headless browser pin for {', '.join(sorted(missing))} in t3")
    return pins


def main() -> None:
    pkg = Package.from_env()
    version = npm_version("t3", "nightly")

    # The `t3` npm package is a shim that downloads the matching archive from
    # the GitHub Release and verifies it against that release's SHA256SUMS.
    release = f"https://github.com/pingdotgg/t3code/releases/download/v{version}"
    hashes = checksums(net.fetch_text(f"{release}/SHA256SUMS"), version)

    # SHA256SUMS lists only the CLI archives; the desktop AppImages are
    # pinned from the electron-updater manifests of the same release.
    desktop = {
        "linux-arm64": appimage_hash(
            net.fetch_text(f"{release}/nightly-linux-arm64.yml"),
            f"T3-Code-{version}-arm64.AppImage",
        ),
        "linux-x64": appimage_hash(
            net.fetch_text(f"{release}/nightly-linux.yml"),
            f"T3-Code-{version}-x86_64.AppImage",
        ),
    }

    # T3 downloads a pinned Chrome for Testing headless shell at runtime,
    # which cannot load its libraries on NixOS, so package the same build.
    # Only the linux-x64 archive, which carries that pin, is downloaded.
    _, tarball = nix.prefetch(f"{release}/t3-{version}-linux-x64.tar.gz", hashes["linux-x64"])
    with tarfile.open(tarball) as archive:
        member = archive.extractfile(f"t3-{version}-linux-x64/t3")
        if member is None:
            raise UpdateError("the linux-x64 archive has no t3 executable")
        pins = browser_pins(member.read())

    write_sources(
        pkg.dir,
        {
            "version": version,
            "hashes": hashes,
            "desktop": {"hashes": desktop},
            "browser": {
                "version": pins["version"],
                "hashes": {
                    "linux-arm64": hex_to_sri(pins["linux-arm64"]),
                    "linux64": hex_to_sri(pins["linux64"]),
                },
            },
        },
    )


if __name__ == "__main__":
    try:
        main()
    except UpdateError as error:
        sys.exit(f"t3code-nightly: {error}")
