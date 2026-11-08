"""Pin upstream's T3 Code desktop app at the nightly whexy/t3code's server
builds, so the app on every Linux host matches the server it connects to."""

from updater import UpdateError, net, nix
from updater.package import Package
from updater.pins import b64_to_sri, write_sources


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


def main() -> None:
    pkg = Package.from_env()
    version = nix.eval_raw(f"{pkg.root}#packages.x86_64-linux.t3code-fork.version")
    release = f"https://github.com/pingdotgg/t3code/releases/download/v{version}"
    write_sources(
        pkg.dir,
        {
            "version": version,
            "hashes": {
                "linux-arm64": appimage_hash(
                    net.fetch_text(f"{release}/nightly-linux-arm64.yml"),
                    f"T3-Code-{version}-arm64.AppImage",
                ),
                "linux-x64": appimage_hash(
                    net.fetch_text(f"{release}/nightly-linux.yml"),
                    f"T3-Code-{version}-x86_64.AppImage",
                ),
            },
        },
    )
