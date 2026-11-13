import io
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from updater import UpdateError, kinds
from updater.package import Package

MANIFEST = {
    "version": "1.2",
    "artifacts": {
        "x86_linux": {
            "checksum": "0809aac7cb58d18f5022b6d05e02aa1974683c0ec430e5f04d25b60ed17de2da"
        },
        "aarch64_linux": {
            "checksum": "3dc39b8fa26f9963cc2038f2966c0932ed5a39f0f9efb39cc0266a261cbbcf76"
        },
    },
}


class KindTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "packages" / "demo").mkdir(parents=True)
        self.pkg = Package(name="demo", version="1.1", system="x86_64-linux", root=self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def sources(self):
        return json.loads((self.pkg.dir / "sources.json").read_text())

    def test_manifest_checksums(self):
        config = {
            "versionSource": {"type": "json", "url": "https://channel", "path": "version"},
            "manifestUrl": "https://dl/?version={version}&file=manifest.json",
            "checksumPath": "artifacts.{platform}.checksum",
            "platforms": {"x86_64-linux": "x86_linux", "aarch64-linux": "aarch64_linux"},
        }
        urls = []

        def fetch_json(url):
            urls.append(url)
            return {"version": "1.2"} if url == "https://channel" else MANIFEST

        with mock.patch("updater.net.fetch_json", fetch_json):
            kinds.manifest_checksums(self.pkg, config)
            self.assertEqual(
                self.sources(),
                {
                    "version": "1.2",
                    "hashes": {
                        "aarch64-linux": "sha256-PcObj6JvmWPMIDjylmwJMu1aOfD577OcwCZqJhy7z3Y=",
                        "x86_64-linux": "sha256-CAmqx8tY0Y9QIrbQXgKqGXRoPA7EMOXwTSW2DtF94to=",
                    },
                },
            )
            self.assertEqual(urls[1], "https://dl/?version=1.2&file=manifest.json")

            # Pinned already: only the version is looked up.
            urls.clear()
            kinds.manifest_checksums(self.pkg, config)
            self.assertEqual(urls, ["https://channel"])

    def test_platform_binaries(self):
        config = {
            "versionSource": {"type": "github", "owner": "o", "repo": "r"},
            "urlTemplate": "https://gh/v{version}/tool-{platform}.tar.gz",
            "platforms": {"x86_64-linux": "linux-amd64", "aarch64-darwin": "darwin-arm64"},
        }
        fetched = []

        def prefetch(url, expected=None):
            fetched.append(url)
            return f"sha256-{url[-20:]}", "/nix/store/x"

        with (
            mock.patch("updater.net.fetch_json", lambda _url: {"tag_name": "v0.3.0"}),
            mock.patch("updater.nix.prefetch", prefetch),
        ):
            kinds.platform_binaries(self.pkg, config)
            self.assertEqual(
                fetched,
                [
                    "https://gh/v0.3.0/tool-darwin-arm64.tar.gz",
                    "https://gh/v0.3.0/tool-linux-amd64.tar.gz",
                ],
            )
            self.assertEqual(self.sources()["version"], "0.3.0")
            self.assertEqual(set(self.sources()["hashes"]), set(config["platforms"]))

            # A platform added to the config re-pins the same version.
            fetched.clear()
            config["platforms"]["aarch64-linux"] = "linux-arm64"
            kinds.platform_binaries(self.pkg, config)
            self.assertEqual(len(fetched), 3)

    def test_pin_prebuilds(self):
        prebuilds = {
            "addon": {
                "urlTemplate": "https://gh/{version}/addon-v{version}-{platform}.tar.gz",
                "platforms": {"x86_64-linux": "linux-x64", "aarch64-darwin": "darwin-arm64"},
            }
        }
        lock = self.pkg.dir / "package-lock.json"
        fetched = []

        def prefetch(url, expected=None):
            fetched.append(url)
            return f"sha256-{url[-20:]}", "/nix/store/x"

        def lock_addon(version):
            lock.write_text(json.dumps({"packages": {"node_modules/addon": {"version": version}}}))

        with mock.patch("updater.nix.prefetch", prefetch):
            lock_addon("2.0.0")
            kinds.pin_prebuilds(self.pkg.dir, prebuilds)
            self.assertEqual(
                fetched,
                [
                    "https://gh/2.0.0/addon-v2.0.0-darwin-arm64.tar.gz",
                    "https://gh/2.0.0/addon-v2.0.0-linux-x64.tar.gz",
                ],
            )
            self.assertEqual(self.sources()["addon"]["version"], "2.0.0")

            # The lock still names the pinned version: nothing is downloaded.
            fetched.clear()
            kinds.pin_prebuilds(self.pkg.dir, prebuilds)
            self.assertEqual(fetched, [])

            lock_addon("2.1.0")
            kinds.pin_prebuilds(self.pkg.dir, prebuilds)
            self.assertEqual(len(fetched), 2)
            self.assertEqual(self.sources()["addon"]["version"], "2.1.0")

            lock.write_text(json.dumps({"packages": {}}))
            with self.assertRaises(UpdateError):
                kinds.pin_prebuilds(self.pkg.dir, prebuilds)

    def test_generate_lockfile(self):
        dest = self.pkg.dir / "package-lock.json"

        def tarball(files):
            path = self.root / "pkg.tgz"
            with tarfile.open(path, "w:gz") as archive:
                for name, content in files.items():
                    data = json.dumps(content).encode()
                    info = tarfile.TarInfo(f"package/{name}")
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))
            return path

        def run(args, *, capture=False, cwd=None, **_kwargs):
            if args[0] == "jq":
                return subprocess.CompletedProcess(args, 0, stdout='{"name": "demo"}')
            # npm updates the lock it finds, and writes package-lock.json
            # only when there is no shrinkwrap.
            self.assertFalse((cwd / "npm-shrinkwrap.json").exists())
            lock = cwd / "package-lock.json"
            seed = json.loads(lock.read_text()) if lock.exists() else {}
            lock.write_text(json.dumps({"seed": seed}))
            return subprocess.CompletedProcess(args, 0)

        with mock.patch("updater.nix.run", run):
            kinds.generate_lockfile(tarball({"package.json": {}}), ".", dest)
            self.assertEqual(json.loads(dest.read_text()), {"seed": {}})

            shrinkwrapped = tarball({"package.json": {}, "npm-shrinkwrap.json": {"pinned": 1}})
            kinds.generate_lockfile(shrinkwrapped, ".", dest)
            self.assertEqual(json.loads(dest.read_text()), {"seed": {"pinned": 1}})

    def test_version_sources(self):
        with mock.patch("updater.net.fetch_json", lambda _url: {"latest": "2.0", "next": "3.0"}):
            self.assertEqual(kinds.latest_version({"type": "npm", "package": "x"}), "2.0")
            self.assertEqual(
                kinds.latest_version({"type": "npm", "package": "x", "tag": "next"}), "3.0"
            )
            with self.assertRaises(UpdateError):
                kinds.latest_version({"type": "npm", "package": "x", "tag": "nightly"})
        with mock.patch("updater.net.fetch_json", lambda _url: {"info": {"version": "0.1.1"}}):
            self.assertEqual(kinds.latest_version({"type": "pypi", "package": "m"}), "0.1.1")

    def test_script_requires_update_py(self):
        with self.assertRaises(UpdateError):
            kinds.script(self.pkg, {})

    def test_unknown_kind(self):
        self.pkg.updater = {"kind": "nope"}
        with self.assertRaises(UpdateError):
            kinds.run_kind(self.pkg)


if __name__ == "__main__":
    unittest.main()


HEAD = {"rev": "a" * 40, "lastModified": 1793155082, "hash": "sha256-" + "A" * 43 + "="}


class GithubBranchTest(unittest.TestCase):
    """The pin follows the default branch's head and carries its commit date."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "packages" / "demo").mkdir(parents=True)
        self.pkg = Package(name="demo", version="0", system="x86_64-linux", root=root)

    def tearDown(self):
        self.tmp.cleanup()

    def pin(self):
        with mock.patch("updater.nix.flake_prefetch", return_value=dict(HEAD)) as prefetch:
            kinds.github_branch(self.pkg, {"owner": "o", "repo": "r"})
        prefetch.assert_called_once_with("github:o/r")
        return json.loads((self.pkg.dir / "sources.json").read_text())

    def test_pins_head_with_its_date(self):
        self.assertEqual(
            self.pin(),
            {"version": "0-unstable-2026-10-28", "rev": HEAD["rev"], "hash": HEAD["hash"]},
        )

    def test_same_head_leaves_pins_alone(self):
        pins = self.pkg.dir / "sources.json"
        pins.write_text(json.dumps({"rev": HEAD["rev"], "kept": True}))
        self.assertTrue(self.pin()["kept"])
