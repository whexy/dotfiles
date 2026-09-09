"""Run with python3 -m unittest discover -s nix/modules/home/panel/ai-quota."""

import json
from pathlib import Path
import subprocess
import unittest


FILTER = Path(__file__).with_name("summary.jq")


def meter(label, used):
    return {"label": label, "percent": used}


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

    def test_exhausted_account_keeps_its_column(self):
        self.plus["meters"] = [meter("5-hour", 100), meter("weekly", 100)]
        result = summarize([self.plus, self.pro])
        self.assertEqual(result["columns"][0]["meters"][0]["remaining"], 0)
        self.assertEqual(len(result["columns"]), 2)

    def test_error_does_not_display_cached_quota(self):
        self.plus["error"] = "offline"
        result = summarize([self.plus, self.pro])
        self.assertEqual(result["columns"][0]["meters"], [None, None])
        self.assertEqual([m["account"] for m in result["detail_meters"]], ["Pro"])

    def test_single_account_and_review_exclusion(self):
        self.pro["meters"].append(meter("review", 100))
        result = summarize([self.pro])
        self.assertEqual(len(result["columns"]), 1)
        self.assertEqual(len(result["columns"][0]["meters"]), 1)

    def test_empty_and_all_failed(self):
        self.assertEqual(summarize([])["columns"], [])
        self.plus["error"] = "offline"
        result = summarize([self.plus])
        self.assertEqual(result["state"], "error")
        self.assertEqual(result["detail_meters"], [])


if __name__ == "__main__":
    unittest.main()
