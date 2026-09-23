"""Run with the packaged interpreter and PYTHONPATH set to its share directory."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtGui import QGuiApplication

from main import Controller, countdown, display_label, fetch, parse_time, project, project_meter, usage


FIXTURE = Path(__file__).with_name("fixture.json")
NOW = datetime(2026, 9, 22, 22, 9, tzinfo=timezone.utc)


class QuotaProjection(unittest.TestCase):
    def test_timeline_uses_actual_reset_and_duration(self):
        data = project_meter({
            "label": "5h", "percent": 3,
            "reset_at": "2026-09-23T03:00:00Z", "duration_seconds": 18000,
        }, NOW, NOW)
        self.assertEqual(data["label"], "5-hour window")
        self.assertAlmostEqual(data["elapsed"], 540 / 18000)
        self.assertEqual(data["used"], 3)
        self.assertEqual(data["countdown"], "4h 51m")
        self.assertEqual([tick["label"] for tick in data["axis"]], ["10:00", "11:15", "12:30", "1:45", "3:00"])

    def test_linear_pace_projection_tints_the_window(self):
        weekly = {"label": "Weekly", "reset_at": "2026-09-26T22:09:00Z", "duration_seconds": 604800}
        over = project_meter({**weekly, "percent": 50}, NOW, NOW)
        self.assertAlmostEqual(over["projection"], 50 / (3 / 7))
        self.assertEqual(over["tint"], "amber")
        self.assertEqual(len(over["axis"]), 8)
        under = project_meter({**weekly, "percent": 10}, NOW, NOW)
        self.assertEqual(under["tint"], "green")

    def test_missing_timing_and_stale_observation_omit_timeline(self):
        for reset, span in [(None, 3600), ("garbage", 3600), ("2026-09-23T00:00:00Z", 0)]:
            with self.subTest(reset=reset, span=span):
                data = project_meter({"percent": 42, "reset_at": reset, "duration_seconds": span}, NOW, NOW)
                self.assertIsNone(data["elapsed"])
                self.assertEqual(data["axis"], [])
        aged = project_meter({"percent": 10, "reset_at": "2026-09-26T22:09:00Z", "duration_seconds": 604800},
                             parse_time("2026-09-22T20:00:00Z"), NOW)
        self.assertIsNone(aged["projection"])
        expired = project_meter({"percent": 10, "reset_at": "2026-09-22T22:00:00Z", "duration_seconds": 18000}, NOW, NOW)
        self.assertEqual((expired["tint"], expired["countdown"]), ("muted", "Reset pending"))
        self.assertIsNone(usage("nan"))
        self.assertEqual(countdown(65), "1m")
        self.assertEqual(display_label("Weekly fable"), "Weekly Fable")

    def test_account_cards_and_absent_providers(self):
        cards = project(fetch(fixture=FIXTURE), now=NOW)
        self.assertEqual([card["id"] for card in cards], ["claude", "codex"])
        account = cards[0]["accounts"][0]
        self.assertEqual(account["plan"], "Max plan")
        self.assertEqual(account["headline"], 13)
        self.assertEqual([meter["label"] for meter in account["meters"]],
                         ["5-hour window", "Weekly", "Weekly Fable"])

    def test_error_account_has_no_meters_or_forecast(self):
        summaries = fetch(fixture=FIXTURE)
        summaries["claude"]["accounts"].append({
            "name": "Offline", "error": "Unavailable", "plan": "Team", "meters": [],
        })
        account = project(summaries, now=NOW)[0]["accounts"][1]
        self.assertEqual(account["meters"], [])
        self.assertIsNone(account["forecast"])
        self.assertEqual(account["error"], "Unavailable")


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

    def width(self):
        return 440

    def height(self):
        return 660

    def setPosition(self, x, y):
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

    def test_payload_shows_only_selected_provider(self):
        controller = Controller(fixture=FIXTURE)
        controller._on_fetched(fetch(fixture=FIXTURE), "")
        controller.selected = "codex"
        self.assertEqual([card["title"] for card in json.loads(controller.payload)["cards"]], ["Codex"])

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
