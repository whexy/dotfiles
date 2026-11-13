"""Pin whexy/t3code's desktop app at the nightly its pinned server builds, so
the app on every Linux host matches the server it connects to. The fork
releases the app once per upstream nightly, under the bare version; until
that release exists, or when its build failed, the previous pin stays."""

from updater import UpdateError, net, nix
from updater.package import Package
from updater.pins import b64_to_sri, write_sources


def appimage(manifest: str) -> tuple[str, str]:
    """The x86_64 AppImage an electron-updater manifest lists, and its hash.
    Its name is the manifest's to choose: T3 dropped the version from it."""
    found = []
    url = None
    for line in manifest.splitlines():
        fields = line.split()
        if fields[:2] == ["-", "url:"] and len(fields) > 2:
            url = fields[2]
        elif fields[:1] == ["sha512:"] and len(fields) > 1 and url is not None:
            if url.endswith("-x86_64.AppImage"):
                found.append((url, b64_to_sri("sha512", fields[1])))
            url = None
    if len(found) != 1:
        raise UpdateError(
            f"expected one x86_64 AppImage in the desktop manifest, found {len(found)}"
        )
    return found[0]


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
    file, digest = appimage(manifest)
    write_sources(pkg.dir, {"version": version, "file": file, "hash": digest})
