"""Pin whexy/t3code's desktop app at the nightly its pinned server builds, so
the app on every Linux host matches the server it connects to. The fork
releases the app once per upstream nightly, under the bare version; until
that release exists, or when its build failed, the previous pin stays."""

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
    manifest_url = f"https://github.com/whexy/t3code/releases/download/{version}/nightly-linux.yml"
    try:
        manifest = net.fetch_text(manifest_url)
    except UpdateError as error:
        if not str(error).endswith("HTTP 404"):
            raise
        print(f"t3code-desktop-nightly: no whexy/t3code desktop release {version}; keeping the pin")
        return
    write_sources(
        pkg.dir,
        {
            "version": version,
            "hash": appimage_hash(manifest, f"T3-Code-{version}-x86_64.AppImage"),
        },
    )
