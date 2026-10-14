import unittest

import transcribe as tr


class AlignTest(unittest.TestCase):
    def test_exact_match_uses_timed_spans(self):
        timed = [("hello", 0.0, 0.5), ("world", 0.6, 1.0)]
        aligned = tr.align_words("hello world", timed, (0.0, 1.0))
        self.assertEqual(
            aligned, [("hello", 0.0, 0.5, True), ("world", 0.6, 1.0, True)]
        )

    def test_substitution_is_interpolated_between_neighbours(self):
        timed = [("deploy", 0.0, 0.5), ("too", 0.5, 0.8), ("prod", 0.8, 1.2)]
        aligned = tr.align_words("deploy to prod", timed, (0.0, 1.2))
        self.assertEqual(aligned[0], ("deploy", 0.0, 0.5, True))
        word, start, end, ok = aligned[1]
        self.assertEqual((word, ok), ("to", False))
        self.assertGreaterEqual(start, 0.5)
        self.assertLessEqual(end, 0.8)
        self.assertEqual(aligned[2], ("prod", 0.8, 1.2, True))

    def test_punctuation_and_case_differences_still_match(self):
        timed = [("Hello,", 0.0, 0.4), ("WORLD.", 0.5, 0.9)]
        aligned = tr.align_words("hello world", timed, (0.0, 0.9))
        self.assertTrue(all(ok for _, _, _, ok in aligned))

    def test_no_timed_words_spreads_over_span(self):
        aligned = tr.align_words("a b", [], (2.0, 4.0))
        self.assertEqual(
            aligned, [("a", 2.0, 3.0, False), ("b", 3.0, 4.0, False)]
        )


class ChunkTest(unittest.TestCase):
    def test_short_file_is_one_chunk(self):
        self.assertEqual(tr.plan_chunks(300.0, []), [(0.0, 300.0)])

    def test_cuts_snap_to_silence_midpoints(self):
        silences = [(590.0, 594.0), (1180.0, 1184.0)]
        chunks = tr.plan_chunks(1800.0, silences, target=600.0)
        self.assertEqual(chunks[0], (0.0, 592.0))
        self.assertEqual(chunks[-1][1], 1800.0)
        for prev, nxt in zip(chunks, chunks[1:]):
            self.assertEqual(prev[1], nxt[0])

    def test_cuts_without_silence_fall_back_to_target(self):
        chunks = tr.plan_chunks(1500.0, [], target=600.0)
        self.assertEqual(chunks[0], (0.0, 600.0))
        self.assertEqual(chunks[-1][1], 1500.0)


def words(*items):
    return [
        {"word": w, "start": s, "end": e, "source": "timed"}
        for w, s, e in items
    ]


class AnnotateTest(unittest.TestCase):
    def test_fillers_pauses_and_stumbles(self):
        ws = words(
            ("um", 0.0, 0.2),
            ("the", 0.3, 0.4),
            ("the", 0.5, 0.6),
            ("plan", 0.7, 0.9),
            ("然后", 2.5, 2.8),
        )
        tr.annotate(ws)
        self.assertTrue(ws[0]["filler"])
        self.assertTrue(ws[1]["stumble"] and ws[2]["stumble"])
        self.assertTrue(ws[4]["filler"])
        self.assertAlmostEqual(ws[3]["gap_after"], 1.6)

    def test_segments_split_on_pauses(self):
        ws = words(("a", 0.0, 0.1), ("b", 0.2, 0.3), ("c", 2.0, 2.1))
        tr.annotate(ws)
        segments = tr.group_segments(ws, 0.6)
        self.assertEqual([s["text"] for s in segments], ["a b", "c"])
        self.assertAlmostEqual(segments[1]["pause_before"], 1.7)


class RenderTest(unittest.TestCase):
    def test_srt_stamps(self):
        segments = [{"start": 61.5, "end": 62.0, "text": "hi"}]
        srt = tr.render_srt(segments)
        self.assertIn("00:01:01,500 --> 00:01:02,000", srt)


if __name__ == "__main__":
    unittest.main()
