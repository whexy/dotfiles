"""Run with python3 -m unittest discover -s modules/home/panel/ai-quota."""

import json
from pathlib import Path
import subprocess
import unittest


FILTER = Path(__file__).with_name("summary.jq")


def meter(label, used, **details):
    return {"label": label, "percent": used, **details}


def summarize(accounts):
    result = subprocess.run(
        ["jq", "-f", str(FILTER), "--arg", "provider", "codex"],
        input=json.dumps({"providers": [{"provider": "codex", "accounts": accounts}]}),
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


class AccountColumns(unittest.TestCase):
    def setUp(self):
        self.plus = {
            "id": "a", "name": "Plus", "error": None,
            "meters": [meter("weekly", 18), meter("5-hour", 15)],
        }
        self.pro = {
            "id": "b", "name": "Pro", "error": None,
            "meters": [meter("weekly", 0)],
        }

    def test_aligned_columns_and_details(self):
        result = summarize([self.pro, self.plus])
        left, right = result["columns"]
        self.assertEqual([left["id"], right["id"]], ["a", "b"])
        self.assertEqual([m["remaining"] for m in left["meters"]], [85, 82])
        self.assertIsNone(right["meters"][0])
        self.assertEqual(right["meters"][1]["remaining"], 100)
        self.assertEqual(left["meters"][1]["color"], "greenDim")
        self.assertEqual([m["account"] for m in result["detail_meters"]],
                         ["Plus", "Plus", "Pro"])
        self.assertEqual(result["columns"], summarize([self.plus, self.pro])["columns"])

    def test_accounts_include_metadata_and_all_coding_windows(self):
        self.plus.update({
            "plan": "Plus", "subtitle": "Work", "observed_at": "2026-09-22T12:00:00Z",
            "observation": {"source": "cached"},
            "meters": [
                meter("monthly", 2),
                meter("weekly", 18),
                meter("daily", 9),
                meter("5-hour", 15, reset_at="2026-09-22T17:00:00Z",
                      reset_in=18000, reset_human="5h", duration_seconds=18000,
                      observation={"source": "live"}),
                meter("review", 100),
            ],
        })
        result = summarize([self.pro, self.plus])
        account = result["accounts"][0]
        self.assertEqual(
            {key: account[key] for key in
             ("id", "name", "plan", "subtitle", "error", "observed_at", "observation")},
            {"id": "a", "name": "Plus", "plan": "Plus", "subtitle": "Work",
             "error": None, "observed_at": "2026-09-22T12:00:00Z",
             "observation": {"source": "cached"}},
        )
        self.assertEqual([m["label"] for m in account["meters"]],
                         ["5h", "Daily", "Weekly", "Monthly"])
        self.assertEqual(len(result["columns"][0]["meters"]), 3)
        self.assertEqual(account["meters"][0]["percent"], 15)
        self.assertEqual(account["meters"][0]["remaining"], 85)
        self.assertEqual(account["meters"][0]["reset_at"], "2026-09-22T17:00:00Z")
        self.assertEqual(account["meters"][0]["reset_in"], 18000)
        self.assertEqual(account["meters"][0]["duration_seconds"], 18000)
        self.assertEqual(account["meters"][0]["span"], 18000)
        self.assertEqual(account["meters"][0]["observation"], {"source": "live"})
        self.assertEqual(result["detail_meters"][0]["reset_at"],
                         "2026-09-22T17:00:00Z")
        self.assertEqual(result["accounts"][1]["plan"], None)
        self.assertEqual(result["accounts"][1]["meters"][0]["reset_at"], None)
        self.assertEqual(result["accounts"][1]["meters"][0]["duration_seconds"], None)
        self.assertNotIn("forecast", account["meters"][0])

    def test_metadata_does_not_change_pill(self):
        before = summarize([self.plus, self.pro])
        self.plus.update({"plan": "Plus", "observed_at": "2026-09-22T12:00:00Z"})
        self.plus["meters"][0].update({"reset_at": "2026-09-29T12:00:00Z",
                                       "observation": "live"})
        after = summarize([self.plus, self.pro])
        for key in ("present", "state", "label", "remaining", "countdown",
                    "countdown_meter", "lines", "compact_lines"):
            self.assertEqual(after[key], before[key])
        for key in ("label", "pill_label", "remaining", "state", "countdown"):
            self.assertEqual(after["display_meter"][key], before["display_meter"][key])

    def test_exhausted_account_keeps_its_column(self):
        self.plus["meters"] = [meter("5-hour", 100), meter("weekly", 100)]
        result = summarize([self.plus, self.pro])
        self.assertEqual(result["columns"][0]["meters"][0]["remaining"], 0)
        self.assertEqual(len(result["columns"]), 2)

    def test_error_does_not_display_cached_quota(self):
        self.plus.update({"error": "offline", "plan": "Plus", "subtitle": "Work",
                          "observed_at": "2026-09-22T12:00:00Z"})
        result = summarize([self.plus, self.pro])
        self.assertEqual(result["columns"][0]["meters"], [None, None])
        self.assertEqual(result["accounts"][0]["meters"], [])
        self.assertEqual(result["accounts"][0]["error"], "offline")
        self.assertEqual(result["accounts"][0]["plan"], "Plus")
        self.assertEqual(result["accounts"][0]["subtitle"], "Work")
        self.assertEqual(result["accounts"][0]["observed_at"], "2026-09-22T12:00:00Z")
        self.assertEqual([m["account"] for m in result["detail_meters"]], ["Pro"])

    def test_single_account_and_review_exclusion(self):
        self.pro["meters"].append(meter("review", 100))
        result = summarize([self.pro])
        self.assertEqual(len(result["columns"]), 1)
        self.assertEqual(len(result["columns"][0]["meters"]), 1)

    def test_empty_and_all_failed(self):
        self.assertEqual(summarize([])["columns"], [])
        self.assertEqual(summarize([])["accounts"], [])
        self.plus["error"] = "offline"
        result = summarize([self.plus])
        self.assertEqual(result["state"], "error")
        self.assertEqual(result["detail_meters"], [])
        self.assertEqual(result["accounts"][0]["meters"], [])

    def test_pct_alias_is_preserved_as_percent(self):
        self.plus["meters"][0].update({"pct": 25, "percent": 99})
        result = summarize([self.plus])
        weekly = result["accounts"][0]["meters"][1]
        self.assertEqual(weekly["percent"], 25)
        self.assertEqual(weekly["remaining"], 75)


if __name__ == "__main__":
    unittest.main()
