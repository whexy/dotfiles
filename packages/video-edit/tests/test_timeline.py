import unittest

from tests import helpers
from video_edit import timeline
from video_edit.media import frames_of
from video_edit.silence import Silences

FPS = helpers.FPS


def validate(edl):
    return timeline.validate(
        edl, helpers.words(), Silences(helpers.SILENCES), FPS, helpers.DURATION
    )


def edl_with(*ranges, overlays=()):
    return {"version": 1, "ranges": list(ranges), "overlays": list(overlays)}


class FrameMathTest(unittest.TestCase):
    def test_frames_round_half_up(self):
        self.assertEqual(frames_of(12.34, 60), 740)
        self.assertEqual(frames_of(0.5 / 60, 60), 1)
        self.assertEqual(frames_of(1867 / 60, 60), 1867)

    def test_out_is_one_past_the_last_frame(self):
        # The 2026-10-13 Resolve session: a 755-frame clip from frame 1112
        # needs endFrame 1867, and the next clip goes at +755.
        ranges = [
            {"src_in": 1112, "src_out": 1867, "section": ""},
            {"src_in": 2385, "src_out": 2689, "section": ""},
        ]
        assembled, total = timeline.assemble(ranges)
        self.assertEqual(assembled[0]["rec_out"] - assembled[0]["rec_in"], 755)
        self.assertEqual(assembled[1]["rec_in"], 755)
        self.assertEqual(total, 755 + 304)

    def test_locate_maps_source_to_record_frames(self):
        assembled, _ = timeline.assemble(
            [{"src_in": 100, "src_out": 200, "section": ""}, {"src_in": 10, "src_out": 20, "section": ""}]
        )
        self.assertEqual(timeline.locate(assembled, 15)[1], 105)
        self.assertEqual(timeline.locate(assembled, 199)[1], 99)
        self.assertIsNone(timeline.locate(assembled, 200))
        self.assertIsNone(timeline.locate(assembled, 50))


class ValidateTest(unittest.TestCase):
    def test_clean_edl_has_no_errors(self):
        result = validate(helpers.default_edl())
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["total"], 62 + 92 + 74)
        overlay = result["overlays"][0]
        self.assertEqual((overlay["rec_in"], overlay["frames"]), (82, 120))

    def test_edge_inside_a_whisper_word_is_fine_in_silence(self):
        words = helpers.words()
        words[2]["end"] = 1.95  # "好" swallowed the pause, as whisper does
        result = timeline.validate(
            helpers.default_edl(), words, Silences(helpers.SILENCES), FPS, helpers.DURATION
        )
        self.assertEqual(result["errors"], [])
        self.assertFalse(any("range 0 end" in w for w in result["warnings"]))

    def test_tight_in_point_is_an_error(self):
        result = validate(edl_with({"start": 59 / FPS, "end": 117 / FPS}))
        self.assertTrue(any("range 0 start" in e and "snap" in e for e in result["errors"]))

    def test_loose_out_point_only_warns(self):
        result = validate(edl_with({"start": 55 / FPS, "end": 140 / FPS}))
        self.assertEqual(result["errors"], [])
        self.assertTrue(any("range 0 end" in w for w in result["warnings"]))

    def test_cut_in_speech_warns_with_the_whisper_word(self):
        result = validate(edl_with({"start": 55 / FPS, "end": 1.3}))
        self.assertEqual(result["errors"], [])
        (warning,) = [w for w in result["warnings"] if "range 0 end" in w]
        self.assertIn("continuous speech", warning)
        self.assertIn("'家'", warning)

    def test_locked_range_downgrades_errors(self):
        result = validate(edl_with({"start": 59 / FPS, "end": 117 / FPS, "lock": True}))
        self.assertEqual(result["errors"], [])

    def test_structural_errors(self):
        cases = {
            "overlap": edl_with(helpers.RANGES[1], {"start": 4.6, "end": 4.75}),
            "keeps no words": edl_with({"start": 0.1, "end": 0.9}),
            "outside the main source": edl_with({"start": 7.0, "end": 9.0}),
            "not after start": edl_with({"start": 2.0, "end": 2.0}),
            "numeric start": edl_with({"start": "1", "end": 2}),
        }
        for needle, edl in cases.items():
            with self.subTest(needle):
                self.assertTrue(
                    any(needle in e for e in validate(edl)["errors"]), validate(edl)["errors"]
                )

    def test_contiguous_ranges_warn(self):
        result = validate(edl_with({"start": 55 / FPS, "end": 117 / FPS}, {"start": 117 / FPS, "end": 285 / FPS}))
        self.assertTrue(any("contiguous" in w for w in result["warnings"]))

    def test_overlay_errors(self):
        base = [dict(r) for r in helpers.RANGES]
        cases = {
            "in a cut": {"slot": "A", "anchor": 2.6, "duration": 1},
            "outside the": {"slot": "A", "anchor": 1.1, "lead": 0.5, "duration": 1},
            "letters, digits": {"slot": "a b", "anchor": 1.1, "duration": 1},
            "lead must be": {"slot": "A", "anchor": 1.1, "lead": -1, "duration": 1},
        }
        for needle, overlay in cases.items():
            with self.subTest(needle):
                errors = validate(edl_with(*base, overlays=[overlay]))["errors"]
                self.assertTrue(any(needle in e for e in errors), errors)
        overlapping = [
            {"slot": "A", "anchor": 4.0, "duration": 1.0},
            {"slot": "B", "anchor": 4.2, "duration": 1.0},
        ]
        errors = validate(edl_with(*base, overlays=overlapping))["errors"]
        self.assertTrue(any("overlap on V3" in e for e in errors))

    def test_overlay_crossing_a_section_warns(self):
        result = validate(helpers.default_edl())
        self.assertTrue(any("G1 crosses the edge of section" in w for w in result["warnings"]))

    def test_fps_must_match(self):
        spec = {"timeline": {"fps": 60}}
        self.assertEqual(timeline.check_fps(spec, {"main": {"fps": 60}}), [])
        self.assertTrue(timeline.check_fps(spec, {"main": {"fps": 30}}))
        self.assertTrue(timeline.check_fps({"timeline": {"fps": 59.94}}, {"main": {"fps": 59.94}}))


class SnapTest(unittest.TestCase):
    def snap(self, edl):
        return timeline.snap(edl, helpers.words(), Silences(helpers.SILENCES), FPS)

    def test_rough_edges_move_into_their_silences(self):
        rough = edl_with({"start": 1.02, "end": 1.65}, {"start": 3.0, "end": 4.55})
        new, report = self.snap(rough)
        r0, r1 = new["ranges"]
        # in-points 0.09 s before onset, out-points 0.25 s after offset
        self.assertAlmostEqual(r0["start"], frames_of(1.0 - 0.09, FPS) / FPS, places=4)
        self.assertAlmostEqual(r0["end"], frames_of(1.7 + 0.25, FPS) / FPS, places=4)
        self.assertAlmostEqual(r1["start"], frames_of(3.3 - 0.09, FPS) / FPS, places=4)
        self.assertAlmostEqual(r1["end"], frames_of(4.5 + 0.25, FPS) / FPS, places=4)
        self.assertEqual(validate(new)["errors"], [])
        self.assertEqual(len(report["moved"]), 4)

    def test_snap_is_idempotent(self):
        new, _ = self.snap(edl_with({"start": 1.02, "end": 1.65}))
        again, report = self.snap(new)
        self.assertEqual(again, new)
        self.assertEqual(report["unchanged"], 2)
        self.assertEqual(report["moved"], [])

    def test_edges_far_from_silence_are_left_for_review(self):
        words = [{"word": "x", "start": 0.0, "end": 10.0, "index": 0}]
        edl = edl_with({"start": 4.0, "end": 6.0})
        new, report = timeline.snap(edl, words, Silences([[9.5, 9.6]]), FPS)
        self.assertEqual(new["ranges"][0]["start"], 4.0)
        self.assertEqual(len(report["speech"]), 2)

    def test_short_silence_takes_the_middle(self):
        words = [{"word": "x", "start": 0.0, "end": 10.0, "index": 0}]
        new, report = timeline.snap(edl_with({"start": 4.0, "end": 6.0}), words, Silences([[3.98, 4.02]]), FPS)
        self.assertEqual(new["ranges"][0]["start"], round(240 / FPS, 4))
        self.assertEqual(report["short"][0]["edge"], "start")

    def test_crossing_ranges_join_on_a_frame_both_edges_accept(self):
        words = [
            {"word": "x", "start": 0.5, "end": 2.0, "index": 0},
            {"word": "y", "start": 2.18, "end": 4.0, "index": 1},
        ]
        silences = Silences([[0.0, 0.5], [2.0, 2.18], [4.0, 4.5]])
        edl = edl_with({"start": 0.4, "end": 2.05}, {"start": 2.15, "end": 4.2})
        new, report = timeline.snap(edl, words, silences, FPS)
        self.assertEqual(report["joined"], [[0, 1]])
        self.assertEqual(new["ranges"][0]["end"], new["ranges"][1]["start"])
        result = timeline.validate(new, words, silences, FPS, 5.0)
        self.assertEqual(result["errors"], [])

    def test_locked_ranges_are_untouched(self):
        edl = edl_with({"start": 1.02, "end": 1.65, "lock": True})
        new, report = self.snap(edl)
        self.assertEqual(new, edl)
        self.assertEqual(report["locked"], [0])

    def test_kept_word_changes_are_reported(self):
        # The proposed out-point cuts "好" in half; snapping keeps all of it.
        _, report = self.snap(edl_with({"start": 0.95, "end": 1.5}))
        self.assertIn("+好", report["kept_words_changed"][0]["change"])


class KeptWordsTest(unittest.TestCase):
    def test_output_times_follow_the_cuts(self):
        result = validate(helpers.default_edl())
        kept = timeline.kept_words(result["ranges"], helpers.words(), FPS)
        self.assertEqual("".join(w["word"] for w in kept), "大家好今天讲kubernetes然后结束")
        jin = next(w for w in kept if w["word"] == "今")
        # range 1 starts at record frame 62, 5 frames before "今"
        self.assertAlmostEqual(jin["out_start"], 67 / FPS, places=4)
        self.assertTrue(jin["cut_before"])
        self.assertNotIn("嗯", [w["word"] for w in kept])


class CameraTest(unittest.TestCase):
    def test_camera_mirrors_ranges_with_offset_and_drift(self):
        assembled, _ = timeline.assemble([{"src_in": 100, "src_out": 300, "section": "", "edl_index": 0, "position": 0}])
        camera = {"offset_frames": 15, "offset_changes": [{"at": 200 / FPS, "offset_frames": 18}], "frames": 10_000}
        items, warnings = timeline.camera_items(assembled, camera, FPS)
        self.assertEqual(warnings, [])
        self.assertEqual(
            [(i["src_in"], i["src_out"], i["rec_in"], i["rec_out"]) for i in items],
            [(85, 185, 0, 100), (182, 282, 100, 200)],
        )

    def test_camera_trimmed_where_it_has_no_footage(self):
        assembled, _ = timeline.assemble([{"src_in": 0, "src_out": 100, "section": "", "edl_index": 0, "position": 0}])
        items, warnings = timeline.camera_items(assembled, {"offset_frames": 15, "frames": 50}, FPS)
        self.assertEqual([(i["src_in"], i["src_out"], i["rec_in"]) for i in items], [(0, 50, 15)])
        self.assertTrue(warnings)


if __name__ == "__main__":
    unittest.main()
