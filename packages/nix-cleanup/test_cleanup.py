from datetime import datetime, timedelta
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import cleanup
from cleanup import Generation, parse_generations, profiles_in, retained


class RetentionTest(unittest.TestCase):
    def test_dense_history_and_calendar_boundaries(self):
        start = datetime(2026, 1, 10, 12)
        generations = [
            Generation(i + 1, start - timedelta(days=i)) for i in range(150)
        ]
        # Five recent; newest in ISO weeks Jan 5, Dec 29, Dec 22, Dec 15;
        # newest in calendar months January, December, November.
        self.assertEqual(retained(generations), {1, 2, 3, 4, 5, 7, 14, 21, 11, 42})

    def test_sparse_history_and_old_current(self):
        generations = [
            Generation(i + 1, datetime(2026, month, day), current=(i == 0))
            for i, (month, day) in enumerate(
                [(1, 1), (4, 1), (8, 1), (10, 1), (10, 2), (10, 3), (10, 4), (10, 5)]
            )
        ]
        self.assertEqual(retained(generations), {1, 2, 3, 4, 5, 6, 7, 8})

    def test_small_history(self):
        self.assertEqual(retained([]), set())
        self.assertEqual(retained([Generation(1, datetime(2026, 1, 1), True)]), {1})

    def test_listing_fails_closed(self):
        self.assertEqual(
            parse_generations("  12   2026-10-31 12:34:56   (current)\n"),
            [Generation(12, datetime(2026, 10, 31, 12, 34, 56), True)],
        )
        for output in ["invalid", "12 2026-10-31 12:34:56"]:
            with self.assertRaises(ValueError):
                parse_generations(output)

    def test_discovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "home-manager-1-link").symlink_to("/nix/store/missing")
            (directory / "home-manager").symlink_to("home-manager-1-link")
            (directory / "abandoned-1-link").symlink_to("/nix/store/missing")
            (directory / "unrelated").touch()
            self.assertEqual(profiles_in(directory), {directory / "home-manager"})

    def test_deletion_and_gc_and_dry_run(self):
        listing = "".join(
            f"{i} 2026-10-31 12:00:{i:02d}" + (" (current)" if i == 8 else "") + "\n"
            for i in range(1, 9)
        )
        for dry_run in [False, True]:
            with (
                patch("sys.argv", ["nix-cleanup"] + (["--dry-run"] if dry_run else [])),
                patch.object(cleanup, "discover_profiles", return_value=[Path("/profile")]),
                patch.object(cleanup.subprocess, "check_output", return_value=listing),
                patch.object(cleanup.subprocess, "run") as run,
            ):
                cleanup.main()
                if dry_run:
                    run.assert_not_called()
                else:
                    self.assertEqual(
                        run.call_args_list[0].args[0],
                        ["nix-env", "--profile", "/profile", "--delete-generations", "1", "2", "3"],
                    )
                    self.assertEqual(run.call_args_list[1].args[0], ["nix-collect-garbage"])

    def test_profile_locations_and_user_scope(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            home.mkdir()
            profiles_root = root / "global"
            own_profiles = profiles_root / "per-user" / cleanup.pwd.getpwuid(cleanup.os.geteuid()).pw_name

            def profile(directory, name):
                directory.mkdir(parents=True, exist_ok=True)
                (directory / f"{name}-1-link").symlink_to("/nix/store/missing")
                result = directory / name
                result.symlink_to(f"{name}-1-link")
                return result

            xdg = root / "xdg"
            expected = {
                profile(xdg / "nix/profiles", "home-manager"),
                profile(home / ".local/state/nix/profiles", "profile"),
                profile(own_profiles, "channels"),
                profile(home, ".nix-profile"),
                profile(home / "legacy", "profile"),
            }
            (home / ".nix-profile").unlink()
            (home / ".nix-profile").symlink_to("legacy/profile")
            profile(home, "unrelated")
            profile(home / "legacy", "unrelated")
            global_profiles = {
                profile(profiles_root, "system"),
                profile(profiles_root / "per-user/another-user", "profile"),
            }
            with (
                patch.object(Path, "home", return_value=home),
                patch.dict(cleanup.os.environ, {"XDG_STATE_HOME": str(xdg)}),
            ):
                self.assertEqual(set(cleanup.discover_profiles(False, profiles_root)), expected)
                self.assertEqual(
                    set(cleanup.discover_profiles(True, profiles_root)), expected | global_profiles
                )

    def test_legacy_global_default_is_root_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            home.mkdir()
            profiles_root = root / "global"
            profiles_root.mkdir()
            for name in ["default", "system"]:
                (profiles_root / f"{name}-1-link").symlink_to("/nix/store/missing")
                (profiles_root / name).symlink_to(f"{name}-1-link")
            legacy = home / ".nix-profile"
            legacy.symlink_to(profiles_root / "default")
            with (
                patch.object(Path, "home", return_value=home),
                patch.dict(cleanup.os.environ, {"XDG_STATE_HOME": str(home / "state")}),
                patch.object(cleanup.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="tester")),
            ):
                with patch.object(cleanup.os, "geteuid", return_value=12345):
                    self.assertEqual(cleanup.discover_profiles(False, profiles_root), [])
                with patch.object(cleanup.os, "geteuid", return_value=0):
                    self.assertEqual(
                        cleanup.discover_profiles(False, profiles_root), [profiles_root / "default"]
                    )
                legacy.unlink()
                legacy.symlink_to("/nix/store/missing")
                with patch.object(cleanup, "profiles_in", wraps=profiles_in) as scan:
                    self.assertEqual(cleanup.discover_profiles(False, profiles_root), [])
                    self.assertNotIn(Path("/nix/store"), [call.args[0] for call in scan.call_args_list])

    def test_gc_and_other_profiles_after_current_generation_rejection(self):
        listing = "".join(
            f"{i} 2026-10-31 12:00:{i:02d}" + (" (current)" if i == 8 else "") + "\n"
            for i in range(1, 9)
        )
        with (
            patch("sys.argv", ["nix-cleanup"]),
            patch.object(cleanup, "discover_profiles", return_value=[Path("/bad"), Path("/good")]),
            patch.object(cleanup.subprocess, "check_output", side_effect=[listing, "1 2026-10-31 12:00:01 (current)"]) as listing_call,
            patch.object(
                cleanup.subprocess,
                "run",
                side_effect=[subprocess.CalledProcessError(1, "nix-env", stderr="Cannot delete current generation"), None],
            ) as run,
        ):
            self.assertEqual(cleanup.main(), 1)
            self.assertEqual(listing_call.call_count, 2)
            self.assertEqual(run.call_count, 2)
            self.assertIn("--delete-generations", run.call_args_list[0].args[0])
            self.assertEqual(run.call_args_list[1].args[0], ["nix-collect-garbage"])

    def test_gc_and_other_profiles_after_malformed_listing(self):
        with (
            patch("sys.argv", ["nix-cleanup"]),
            patch.object(cleanup, "discover_profiles", return_value=[Path("/bad"), Path("/good")]),
            patch.object(cleanup.subprocess, "check_output", side_effect=["unexpected output", "1 2026-10-31 12:00:01 (current)"]) as listing_call,
            patch.object(cleanup.subprocess, "run") as run,
        ):
            self.assertEqual(cleanup.main(), 1)
            self.assertEqual(listing_call.call_count, 2)
            run.assert_called_once_with(["nix-collect-garbage"], check=True)

    def test_system_mode_requires_root(self):
        with (
            patch("sys.argv", ["nix-cleanup", "--system"]),
            patch.object(cleanup.os, "geteuid", return_value=12345),
            patch.object(cleanup, "discover_profiles") as discovery,
            patch.object(cleanup.subprocess, "run") as run,
        ):
            with self.assertRaises(SystemExit) as error:
                cleanup.main()
            self.assertEqual(error.exception.code, 2)
            discovery.assert_not_called()
            run.assert_not_called()

    def test_discovery_failure_does_not_block_other_profiles_or_gc(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            good = home / "state/nix/profiles/home-manager"
            good.parent.mkdir(parents=True)
            good.symlink_to("home-manager-1-link")
            (good.parent / "home-manager-1-link").symlink_to("/nix/store/missing")
            bad = home / ".local/state/nix/profiles"

            def scan(directory):
                if directory == bad:
                    raise PermissionError("unreadable directory")
                return profiles_in(directory)

            discover = cleanup.discover_profiles
            with (
                patch("sys.argv", ["nix-cleanup"]),
                patch.object(Path, "home", return_value=home),
                patch.dict(cleanup.os.environ, {"XDG_STATE_HOME": str(home / "state")}),
                patch.object(cleanup, "profiles_in", side_effect=scan),
                patch.object(cleanup, "discover_profiles", side_effect=lambda system, on_error: discover(system, home / "global", on_error)),
                patch.object(cleanup.subprocess, "check_output", return_value="1 2026-10-31 12:00:01 (current)") as listing,
                patch.object(cleanup.subprocess, "run") as run,
            ):
                self.assertEqual(cleanup.main(), 1)
                listing.assert_called_once()
                self.assertEqual(listing.call_args.args[0][2], str(good))
                run.assert_called_once_with(["nix-collect-garbage"], check=True)


if __name__ == "__main__":
    unittest.main()
