"""Run with the packaged interpreter and PYTHONPATH set to its share directory."""

from datetime import datetime, timezone
import os
from pathlib import Path
import unittest
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtGui import QGuiApplication

from main import Controller, countdown, fetch, parse_time, percentage, project, project_meter


FIXTURE = Path(__file__).with_name("fixture.json")
NOW = datetime(2026, 9, 22, 22, 9, tzinfo=timezone.utc)


class QuotaProjection(unittest.TestCase):
    def test_timeline_uses_actual_reset_and_duration(self):
        data = project_meter({
            "label": "5h", "remaining": 97,
            "reset_at": "2026-09-23T03:00:00Z", "duration_seconds": 18000,
        }, NOW)
        self.assertTrue(data["timed"])
        self.assertAlmostEqual(data["timeFraction"], 540 / 18000)
        self.assertEqual(data["remaining"], 97)
        self.assertEqual(data["reset"], "Resets in 4h 51m")

    def test_missing_or_invalid_timing_omits_axis(self):
        for reset, span in [(None, 3600), ("garbage", 3600), ("2026-09-23T00:00:00Z", 0)]:
            with self.subTest(reset=reset, span=span):
                data = project_meter({"remaining": 42, "reset_at": reset, "duration_seconds": span}, NOW)
                self.assertFalse(data["timed"])
                self.assertEqual(data["reset"], "Reset unavailable")
        self.assertIsNone(percentage("nan"))
        self.assertIsNone(parse_time("invalid"))
        self.assertEqual(countdown(65), "2m")

    def test_all_account_windows_and_absent_providers(self):
        summaries = fetch(fixture=FIXTURE)
        cards = project(summaries, now=NOW)
        self.assertEqual([card["id"] for card in cards], ["claude", "codex"])
        self.assertEqual(cards[0]["remaining"], 85)
        self.assertEqual(cards[0]["accounts"][0]["plan"], "Max plan")
        self.assertEqual([meter["label"] for meter in cards[0]["accounts"][0]["meters"]],
                         ["5h", "Weekly", "Weekly fable"])

    def test_error_account_is_not_a_meter(self):
        summaries = fetch(fixture=FIXTURE)
        summaries["claude"]["accounts"].append({
            "name": "Offline", "error": "Unavailable", "plan": "Team", "meters": [],
        })
        card = project(summaries, now=NOW)[0]
        self.assertEqual(card["accounts"][1]["meters"], [])
        self.assertEqual(card["accounts"][1]["error"], "Unavailable")


class FakeWindow:
    def __init__(self):
        self.visible = False

    def isVisible(self):
        return self.visible

    def show(self):
        self.visible = True

    def hide(self):
        self.visible = False

    def raise_(self):
        pass

    def requestActivate(self):
        pass


class PopupLifecycle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def test_same_provider_hides_and_other_provider_reuses_window(self):
        controller = Controller(fixture=FIXTURE)
        window = FakeWindow()
        controller.window = window
        with patch.object(controller, "refresh"):
            controller.toggle("claude")
            self.assertTrue(window.visible)
            controller.toggle("codex")
            self.assertTrue(window.visible)
            self.assertEqual(controller.selected, "codex")
            controller.toggle("codex")
            self.assertFalse(window.visible)
            controller.toggle("unknown")
            self.assertFalse(window.visible)
        controller.timer.stop()

    def test_failed_refresh_retains_but_marks_last_good_data_stale(self):
        controller = Controller(fixture=FIXTURE)
        controller._on_fetched(fetch(fixture=FIXTURE), "")
        self.assertTrue(controller.cards)
        controller._on_fetched(None, "timeout")
        self.assertTrue(controller.stale)
        self.assertTrue(controller.cards)
        self.assertEqual(controller.error, "Could not refresh quota")

    def test_old_upstream_snapshot_is_marked_stale(self):
        controller = Controller(fixture=FIXTURE)
        result = fetch(fixture=FIXTURE)
        result["_updated_at"] = "2000-01-01T00:00:00Z"
        controller._on_fetched(result, "")
        self.assertTrue(controller.stale)
        self.assertEqual(controller.error, "Quota data has not updated")

    def test_old_account_observation_is_marked_stale(self):
        controller = Controller(fixture=FIXTURE)
        result = fetch(fixture=FIXTURE)
        result["_updated_at"] = datetime.now(timezone.utc).isoformat()
        result["claude"]["accounts"][0]["observed_at"] = "2000-01-01T00:00:00Z"
        controller._on_fetched(result, "")
        self.assertTrue(controller.stale)


if __name__ == "__main__":
    unittest.main()
