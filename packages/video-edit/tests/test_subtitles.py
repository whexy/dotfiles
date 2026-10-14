import json
import unittest

from tests import helpers
from video_edit import build, subtitles
from video_edit.common import read_json, write_json

GOOD = [
    {"from": 0, "to": 2, "text": "大家好"},
    {"from": 3, "to": 7, "text": "今天讲 Kubernetes"},
    {"from": 8, "to": 11, "text": "然后结束"},
]


class SubtitleTest(unittest.TestCase):
    def setUp(self):
        self.edit = helpers.EditRoot()
        self.root = self.edit.root
        code, payload = build.run_build(self.root)
        self.assertEqual(code, 0, payload)

    def tearDown(self):
        self.edit.close()

    def srt(self, cues, **kwargs):
        path = self.edit.tmp / "cues.json"
        path.write_text(json.dumps(cues, ensure_ascii=False), encoding="utf-8")
        return subtitles.run_srt(self.root, path, **kwargs)

    def test_words_view(self):
        code, text = subtitles.run_words(self.root)
        self.assertEqual(code, 0)
        self.assertIn("## cut 1 · S01 · 00:01.03", text)
        self.assertIn("3      00:01.12  今|天|讲|k|ubernetes", text)
        code, data = subtitles.run_words(self.root, section="S02", as_json=True)
        self.assertEqual([w["i"] for w in data["words"]], [8, 9, 10, 11])

    def test_srt_on_the_timeline_clock(self):
        code, payload = self.srt(GOOD)
        self.assertEqual(code, 0, payload)
        text = (self.root / payload["srt"]).read_text(encoding="utf-8")
        blocks = text.strip().split("\n\n")
        self.assertEqual(len(blocks), 3)
        # first word 5 frames into the timeline, held until the next cue
        self.assertIn("01:00:00,083 --> 01:00:01,117\n大家好", blocks[0])
        self.assertIn("01:00:02,650 --> 01:00:03,850\n然后结束", blocks[2])
        self.assertEqual(payload["srt"], "subtitles/Demo_v1.srt")
        code, payload = self.srt(GOOD, start_tc="00:00:00:00")
        self.assertEqual(payload["first"], "00:00:00,083")

    def test_every_word_in_exactly_one_cue(self):
        cases = {
            "words 3-3 are in no cue": [GOOD[0], {**GOOD[1], "from": 4}, GOOD[2]],
            "overlapping the previous cue": [GOOD[0], {**GOOD[1], "from": 2}, GOOD[2]],
            "words 11-11 are in no cue": [GOOD[0], GOOD[1], {**GOOD[2], "to": 10}],
            "not a range of kept words": [GOOD[0], GOOD[1], {**GOOD[2], "to": 40}],
        }
        for needle, cues in cases.items():
            with self.subTest(needle):
                code, payload = self.srt(cues)
                self.assertEqual(code, 1)
                self.assertTrue(any(needle in e for e in payload["errors"]), payload["errors"])

    def test_line_width_and_duration_limits(self):
        wide = [{**GOOD[0], "text": "大家好" * 6}, GOOD[1], GOOD[2]]
        code, payload = self.srt(wide)
        self.assertTrue(any("wide, max 17" in e for e in payload["errors"]))
        short = [{"from": 0, "to": 0, "text": "大"}, {"from": 1, "to": 2, "text": "家好"}, GOOD[1], GOOD[2]]
        code, payload = self.srt(short)
        self.assertTrue(any("cue 0: shows 0.20s" in e for e in payload["errors"]), payload)
        spec = read_json(self.root.spec_path)
        spec["subtitles"]["maxDuration"] = 1.0
        write_json(self.root.spec_path, spec)
        code, payload = self.srt(GOOD)
        self.assertTrue(any("split it" in e for e in payload["errors"]))

    def test_glossary_fixes_text_not_timings(self):
        cues = [GOOD[0], {**GOOD[1], "text": "今天讲 telscope"}, GOOD[2]]
        code, payload = self.srt(cues)
        self.assertEqual(code, 0, payload)
        text = (self.root / payload["srt"]).read_text(encoding="utf-8")
        self.assertIn("今天讲 Tailscale", text)

    def test_misindexed_text_warns(self):
        cues = [GOOD[0], {**GOOD[1], "text": "完全无关的句子"}, GOOD[2]]
        code, payload = self.srt(cues)
        self.assertEqual(code, 0)
        self.assertTrue(any("differs a lot" in w for w in payload["warnings"]))

    def test_clock_helpers(self):
        self.assertEqual(subtitles.stamp(3600 + 61.5), "01:01:01,500")
        self.assertEqual(subtitles.tc_seconds("01:00:00:30", 60), 3600.5)


if __name__ == "__main__":
    unittest.main()
