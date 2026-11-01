import tempfile
import unittest
from pathlib import Path

from updater import UpdateError
from updater.pins import (
    compare_versions,
    dig,
    hex_to_sri,
    interpolate,
    read_sources,
    replace_once,
    strip_v,
    write_sources,
)


class HashTest(unittest.TestCase):
    def test_sha256_hex(self):
        self.assertEqual(
            hex_to_sri("0809aac7cb58d18f5022b6d05e02aa1974683c0ec430e5f04d25b60ed17de2da"),
            "sha256-CAmqx8tY0Y9QIrbQXgKqGXRoPA7EMOXwTSW2DtF94to=",
        )

    def test_sha512_hex(self):
        self.assertTrue(hex_to_sri("ab" * 64).startswith("sha512-"))

    def test_rejects_other_lengths(self):
        with self.assertRaises(UpdateError):
            hex_to_sri("abcd")
        with self.assertRaises(UpdateError):
            hex_to_sri("z" * 64)


class TemplateTest(unittest.TestCase):
    def test_fills_placeholders(self):
        self.assertEqual(
            interpolate("a/v{version}/{platform}.tgz", version="1.2", platform="linux"),
            "a/v1.2/linux.tgz",
        )

    def test_unknown_placeholder(self):
        with self.assertRaises(UpdateError):
            interpolate("{version}/{arch}", version="1")

    def test_dig(self):
        doc = {"artifacts": {"x86_linux": {"checksum": "c"}}}
        self.assertEqual(dig(doc, "artifacts.x86_linux.checksum"), "c")
        with self.assertRaises(UpdateError):
            dig(doc, "artifacts.arm.checksum")


class VersionTest(unittest.TestCase):
    def test_strip_v(self):
        self.assertEqual(strip_v("v1.2.3"), "1.2.3")
        self.assertEqual(strip_v("1.2.3"), "1.2.3")
        self.assertEqual(strip_v("very"), "very")

    def test_matches_nix_compare_versions(self):
        # Pairs from Nix's own compareVersions tests, plus this repo's formats.
        lower = [
            ("1.0", "2.3"),
            ("2.1", "2.3"),
            ("2.3", "2.3.1"),
            ("2.3a", "2.3.1"),
            ("2.3pre1", "2.3"),
            ("2.3pre3", "2.3pre12"),
            ("2.3a", "2.3c"),
            ("2.3pre1", "2.3c"),
            ("2.3pre1", "2.3q"),
            ("0.1.7-nightly.20261031.4000", "0.1.7-nightly.20261101.3990"),
            ("1.4.14-R7309.1", "1.4.14-R7310.1"),
            ("1.0.0-beta.9", "1.0.0-beta.26"),
            ("0-unstable-2025-04-16", "0-unstable-2026-01-02"),
        ]
        for a, b in lower:
            with self.subTest(a=a, b=b):
                self.assertEqual(compare_versions(a, b), -1)
                self.assertEqual(compare_versions(b, a), 1)
        self.assertEqual(compare_versions("2.3", "2.3"), 0)
        self.assertEqual(compare_versions("2.3-1", "2.3.1"), 0)


class SourcesTest(unittest.TestCase):
    def test_round_trip_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            pkg = Path(tmp)
            self.assertEqual(read_sources(pkg), {})
            write_sources(pkg, {"version": "1", "hashes": {"x86_64-linux": "sha256-a"}})
            self.assertEqual(
                (pkg / "sources.json").read_text(),
                '{\n  "version": "1",\n  "hashes": {\n    "x86_64-linux": "sha256-a"\n  }\n}\n',
            )
            self.assertEqual(read_sources(pkg)["version"], "1")

    def test_replace_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "default.nix"
            path.write_text('rev = "abc"; other = "abc";')
            with self.assertRaises(UpdateError):
                replace_once(path, "abc", "def")
            replace_once(path, 'rev = "abc"', 'rev = "def"')
            self.assertEqual(path.read_text(), 'rev = "def"; other = "abc";')


if __name__ == "__main__":
    unittest.main()
