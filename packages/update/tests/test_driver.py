import tempfile
import unittest
from pathlib import Path
from unittest import mock

from updater import UpdateError, driver
from updater.package import Package


class SnapshotTest(unittest.TestCase):
    def test_restore_undoes_edits_and_new_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            pkg = Path(tmp)
            (pkg / "default.nix").write_text("old")
            (pkg / "sub").mkdir()
            (pkg / "sub" / "lock.json").write_text("{}")
            saved = driver.snapshot(pkg)
            self.assertEqual(driver.changed_files(pkg, saved), [])

            (pkg / "default.nix").write_text("new")
            (pkg / "sources.json").write_text("{}")
            (pkg / "sub" / "lock.json").unlink()
            self.assertEqual(
                [p.name for p in driver.changed_files(pkg, saved)],
                ["default.nix", "sources.json", "lock.json"],
            )

            driver.restore(pkg, saved)
            self.assertEqual((pkg / "default.nix").read_text(), "old")
            self.assertFalse((pkg / "sources.json").exists())
            self.assertEqual((pkg / "sub" / "lock.json").read_text(), "{}")


class CommitMessageTest(unittest.TestCase):
    def test_version_change(self):
        self.assertEqual(
            driver.commit_message("asc", "6.3.0", "6.4.0", "https://x/6.4.0"),
            ["chore(asc): 6.3.0 -> 6.4.0", "Changelog: https://x/6.4.0"],
        )

    def test_same_version_without_changelog(self):
        self.assertEqual(driver.commit_message("cf", "1", "1", None), ["chore(cf): refresh 1 pins"])


class UpdateTest(unittest.TestCase):
    """A failing step leaves the package as it was."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "packages" / "demo").mkdir(parents=True)
        (root / "packages" / "demo" / "sources.json").write_text('{"version": "2"}\n')
        self.pkg = Package(
            name="demo",
            version="2",
            system="x86_64-linux",
            root=root,
            updater={"kind": "demo"},
        )
        self.patches = [
            mock.patch("updater.nix.git", lambda *_a, **_k: ""),
            mock.patch("updater.nix.run"),
        ]
        for patch in self.patches:
            patch.start()

    def tearDown(self):
        for patch in self.patches:
            patch.stop()
        self.tmp.cleanup()

    def write_version(self, version):
        def kind(pkg):
            (pkg.dir / "sources.json").write_text(f'{{"version": "{version}"}}\n')

        return mock.patch("updater.driver.run_kind", kind)

    def evaluates_to(self, version):
        return mock.patch(
            "updater.nix.eval_json", lambda *_a, **_k: {"version": version, "changelog": None}
        )

    def test_unchanged(self):
        with mock.patch("updater.driver.run_kind", lambda _pkg: None):
            self.assertIsNone(driver.update(self.pkg, commit=False))

    def test_downgrade_is_refused_and_reverted(self):
        with self.write_version("1"), self.evaluates_to("1"), self.assertRaises(UpdateError):
            driver.update(self.pkg, commit=False)
        self.assertEqual((self.pkg.dir / "sources.json").read_text(), '{"version": "2"}\n')

    def test_downgrade_allowed(self):
        self.pkg.updater["allowDowngrade"] = True
        with (
            self.write_version("1"),
            self.evaluates_to("1"),
            mock.patch("updater.driver.check_targets"),
        ):
            self.assertEqual(driver.update(self.pkg, commit=False), "1")

    def test_failed_build_reverts(self):
        def fail(*_a):
            raise UpdateError("build failed")

        with (
            self.write_version("3"),
            self.evaluates_to("3"),
            mock.patch("updater.driver.check_targets", fail),
            self.assertRaises(UpdateError),
        ):
            driver.update(self.pkg, commit=False)
        self.assertEqual((self.pkg.dir / "sources.json").read_text(), '{"version": "2"}\n')

    def test_broken_skills_revert_only_this_package(self):
        out = Path(self.tmp.name) / "out"
        (out / "share" / "skills" / "demo").mkdir(parents=True)
        outputs = [[str(out)] if s == "x86_64-linux" else None for s in driver.FLAKE_SYSTEMS]

        def run(args, **_kwargs):
            if args[-1].endswith(f"#checks.x86_64-linux.{driver.SKILLS_CHECK}"):
                raise UpdateError("nix exited 1")

        evals = [{"version": "3", "changelog": None}, outputs, True]
        with (
            self.write_version("3"),
            mock.patch("updater.nix.eval_json", side_effect=evals),
            mock.patch("updater.nix.run", side_effect=run),
            self.assertRaisesRegex(
                UpdateError, f"^checks.x86_64-linux.{driver.SKILLS_CHECK} fails"
            ),
        ):
            driver.update(self.pkg, commit=False)
        self.assertEqual((self.pkg.dir / "sources.json").read_text(), '{"version": "2"}\n')


class CheckTargetsTest(unittest.TestCase):
    """The skills check runs only for outputs that ship skills."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "out"
        self.out.mkdir()
        self.pkg = Package(
            name="demo",
            version="2",
            system="x86_64-linux",
            root=Path(self.tmp.name),
            updater={"kind": "demo"},
        )

    def tearDown(self):
        self.tmp.cleanup()

    def built(self, *, has_check=True):
        outputs = [[str(self.out)] if s == "x86_64-linux" else None for s in driver.FLAKE_SYSTEMS]
        with (
            mock.patch("updater.nix.eval_json", side_effect=[outputs, has_check]),
            mock.patch("updater.nix.run") as run,
        ):
            driver.check_targets(self.pkg, ["demo"])
        return [call.args[0][-1].split("#", 1)[1] for call in run.call_args_list]

    def test_package_without_skills(self):
        self.assertEqual(self.built(), ["packages.x86_64-linux.demo"])

    def test_package_with_skills(self):
        (self.out / "share" / "skills" / "demo").mkdir(parents=True)
        self.assertEqual(
            self.built(),
            ["packages.x86_64-linux.demo", f"checks.x86_64-linux.{driver.SKILLS_CHECK}"],
        )

    def test_system_without_the_check(self):
        (self.out / "share" / "skills" / "demo").mkdir(parents=True)
        self.assertEqual(self.built(has_check=False), ["packages.x86_64-linux.demo"])


if __name__ == "__main__":
    unittest.main()
