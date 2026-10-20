from contextlib import redirect_stderr, redirect_stdout
import io
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import transcribe as tr


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
    return [{"word": w, "start": s, "end": e} for w, s, e in items]


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


def stumbles(*items):
    ws = words(*items)
    tr.annotate(ws)
    return "".join(w["word"] if w["stumble"] else "." for w in ws)


class StumbleTest(unittest.TestCase):
    """Pieces and timings as whisper-1 returned them for the user's footage."""

    def test_repeated_phrase_split_into_hanzi(self):
        self.assertEqual(
            stumbles(
                ("刚", 89.12, 89.28), ("才", 89.28, 89.48),
                ("其实", 89.48, 89.84), ("最", 90.26, 90.78),
                ("后", 90.78, 90.96), ("最", 90.96, 91.16),
                ("后", 91.16, 91.3), ("就是", 91.3, 91.6),
            ),
            "...最后最后.",
        )
        self.assertEqual(
            stumbles(
                ("一个", 131.34, 131.74), ("虚", 131.74, 131.8),
                ("拟", 131.8, 131.88), ("机", 131.88, 132.06),
                ("虚", 132.28, 132.68), ("拟", 132.68, 132.68),
                ("机", 132.68, 132.74), ("里", 132.74, 132.96),
            ),
            ".虚拟机虚拟机.",
        )

    def test_reduplication_is_not_a_stumble(self):
        for case in [
            (("我", 3.88, 4.0), ("刚", 4.0, 4.12), ("刚", 4.12, 4.22), ("说", 4.22, 4.36)),
            (("访", 278.3, 278.42), ("问", 278.42, 278.5), ("它", 278.5, 278.76),
             ("它", 278.76, 279.08), ("就是", 279.08, 279.38)),
            (("需要", 33.28, 33.42), ("一", 33.42, 33.64), ("台", 33.64, 33.64),
             ("一", 33.64, 33.82), ("台", 33.82, 33.86), ("去", 33.86, 34.1)),
        ]:
            with self.subTest("".join(w for w, _, _ in case)):
                self.assertEqual(stumbles(*case), "." * len(case))

    def test_segmentation_and_case_do_not_hide_a_repeat(self):
        self.assertEqual(
            stumbles(("最后", 0.0, 0.4), ("最", 0.5, 0.6), ("后", 0.6, 0.7), ("的", 0.7, 0.8)),
            "最后最后.",
        )
        self.assertEqual(
            stumbles(("sk", 6.08, 6.36), ("ills", 6.36, 6.4), ("Sk", 6.5, 6.6),
                     ("ills,", 6.6, 6.7), ("那", 6.7, 6.8)),
            "skillsSkills,.",
        )

    def test_takes_far_apart_are_not_a_stumble(self):
        self.assertEqual(
            stumbles(("最", 0.0, 0.2), ("后", 0.2, 0.4), ("最", 1.9, 2.1), ("后", 2.1, 2.3)),
            "....",
        )


class CollapseTest(unittest.TestCase):
    def test_only_silences_no_word_gap_accounts_for_remain(self):
        ws = words(
            ("比如", 3.34, 3.74), ("它", 34.28, 34.52), ("所以", 35.44, 35.84),
            ("这", 10.54, 10.86), ("就", 10.86, 11.94), ("读", 11.94, 11.94),
        )
        ws.sort(key=lambda w: w["start"])
        silences = [
            (1.06, 3.11),  # dead air before the first word
            (11.23, 11.59),  # a pause whisper-1 stretched 就 over
            (34.38, 35.52),  # the 它/所以 gap, overhanging both word edges
        ]
        self.assertEqual(
            tr.collapse_silences(silences, ws), [(1.06, 3.11), (11.23, 11.59)]
        )


# Uniform noise peaking at -35.9 dBFS has an RMS of -40.7 dBFS.
NOISE = 0.016
NOISE_RMS_DB = 20 * math.log10(NOISE / math.sqrt(3))
TONE_OFF = [(2.0, 3.0), (5.0, 5.6), (8.0, 10.0)]


def synth(path, noise):
    """10 s at 16 kHz: a 440 Hz tone muted over TONE_OFF, over uniform
    noise peaking at `noise` (0 leaves the muted spans digitally silent)."""
    off = "+".join(
        f"gte(t,{a})" if b >= 10 else f"between(t,{a},{b})" for a, b in TONE_OFF
    )
    inputs = ["-f", "lavfi", "-i", "sine=f=440:r=16000:d=10"]
    graph = f"[0]volume=0:enable='{off}'"
    if noise:
        inputs += [
            "-f", "lavfi", "-i",
            f"anoisesrc=d=10:c=white:r=16000:a={noise}:seed=1",
        ]
        graph += "[t];[t][1]amix=inputs=2:normalize=0"
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", graph, str(path)],
        check=True,
    )
    return path


@unittest.skipUnless(shutil.which("ffmpeg"), "needs ffmpeg")
class SilenceTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def assertSpans(self, found, expected):
        # volume's enable switches per 1024-sample frame, so edges move by
        # up to 64 ms.
        self.assertEqual(len(found), len(expected), found)
        for (s, e), (xs, xe) in zip(found, expected):
            self.assertAlmostEqual(s, xs, delta=0.1)
            self.assertAlmostEqual(e, xe, delta=0.1)

    def test_auto_threshold_sits_above_the_noise_floor(self):
        wav = synth(self.dir / "noisy.wav", NOISE)
        settings = tr.silence_settings(wav, "auto")
        self.assertAlmostEqual(settings["noise_floor_db"], NOISE_RMS_DB, delta=1.0)
        self.assertAlmostEqual(
            settings["threshold_db"],
            settings["noise_floor_db"] + tr.FLOOR_MARGIN_DB,
            places=2,
        )
        self.assertSpans(tr.detect_silences(wav, settings, 10.0), TONE_OFF)

    def test_explicit_threshold_below_the_noise_finds_nothing(self):
        wav = synth(self.dir / "noisy.wav", NOISE)
        settings = tr.silence_settings(wav, -40.0)
        self.assertEqual(settings["noise_floor_db"], None)
        self.assertEqual(tr.detect_silences(wav, settings, 10.0), [])

    def test_digital_silence_falls_back(self):
        wav = synth(self.dir / "gated.wav", 0)
        settings = tr.silence_settings(wav, "auto")
        self.assertEqual(
            (settings["noise_floor_db"], settings["threshold_db"]),
            (None, tr.SILENCE_FALLBACK_DB),
        )
        self.assertSpans(tr.detect_silences(wav, settings, 10.0), TONE_OFF)

    def test_process_records_the_threshold(self):
        # FLAC takes the extraction path, which detects on the 64 kbps mp3.
        flac = synth(self.dir / "talk.flac", NOISE)
        timed = {
            "language": "english",
            "words": [
                {"word": "a", "start": 0.1, "end": 1.9},
                {"word": "b", "start": 3.1, "end": 4.9},
                {"word": "c", "start": 5.7, "end": 7.9},
            ],
        }
        for flags in ([], ["--silence-db", "-40"]):
            with self.subTest(flags=flags), redirect_stderr(io.StringIO()):
                result = tr.process(
                    tr.parse_args([str(flac), *flags]), lambda *_: timed
                )
                silence = result["silence"]
                if flags:
                    self.assertEqual(silence["threshold_db"], -40.0)
                    self.assertEqual(result["silences"], [])
                else:
                    self.assertAlmostEqual(
                        silence["noise_floor_db"], NOISE_RMS_DB, delta=1.5
                    )
                    # The two inner silences are the a/b and b/c gaps.
                    self.assertSpans(result["silences"], [(8.0, 10.0)])
                self.assertEqual(silence["min_duration"], tr.SILENCE_MIN)


class RenderTest(unittest.TestCase):
    def test_srt_stamps(self):
        segments = [{"start": 61.5, "end": 62.0, "text": "hi"}]
        srt = tr.render_srt(segments)
        self.assertIn("00:01:01,500 --> 00:01:02,000", srt)

    def test_rounding_carries_into_the_next_unit(self):
        srt = tr.render_srt([{"start": 1.9996, "end": 59.9996, "text": "hi"}])
        self.assertIn("00:00:02,000 --> 00:01:00,000", srt)
        self.assertEqual(tr.ts(59.996), "01:00.00")
        self.assertEqual(tr.ts(61.5), "01:01.50")


RAW_WORDS = (
    ("So", 0.0, 0.3),
    ("um,", 0.5, 0.7),
    ("the", 0.8, 0.9),
    ("the", 1.0, 1.1),
    ("plan", 1.2, 1.5),
    ("works.", 2.5, 2.9),
    ("然后", 5.0, 5.3),
    ("deploy.", 5.4, 5.9),
)
# The first two lie inside word gaps and collapse; the trailing one is dead air.
RAW_SILENCES = [(1.5, 2.5), (2.9, 5.0), (6.0, 9.0)]
RAW_SILENCE = {"threshold_db": -35.48, "min_duration": 0.5, "noise_floor_db": -44.48}


def live_result(pause, no_silence):
    """What `process` returns for RAW_WORDS under these flags."""
    ws = words(*RAW_WORDS)
    tr.annotate(ws)
    return {
        "source": "talk.mp4",
        "duration": 9.0,
        "model": tr.MODEL,
        "languages": ["en", "zh"],
        "estimated_cost_usd": 0.0009,
        "timings": {"media_seconds": 0.12, "api_seconds": 2.3},
        "segments": tr.group_segments(ws, pause),
        "silence": None if no_silence else RAW_SILENCE,
        "silences": tr.collapse_silences([] if no_silence else RAW_SILENCES, ws),
    }


def run_main(argv):
    out = io.StringIO()
    with (
        redirect_stdout(out),
        redirect_stderr(io.StringIO()),
        mock.patch.dict(os.environ, {"OPENAI_API_KEY": ""}),
    ):
        code = tr.main(argv)
    return code, out.getvalue()


class FromJsonTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.cache = self.dir / "talk.json"
        self.cache.write_text(
            tr.render(live_result(0.6, False), "json"), encoding="utf-8"
        )

    def test_matches_a_live_run_with_the_same_flags(self):
        texts = set()
        for pause, no_silence in [(0.6, False), (1.5, False), (0.6, True), (1.5, True)]:
            flags = ["--pause", str(pause)] + (["--no-silence"] if no_silence else [])
            for fmt in ("text", "json", "srt"):
                with self.subTest(pause=pause, no_silence=no_silence, fmt=fmt):
                    code, out = run_main(
                        ["--from-json", str(self.cache), "--format", fmt, *flags]
                    )
                    self.assertEqual(code, tr.EXIT_OK)
                    self.assertEqual(
                        out, tr.render(live_result(pause, no_silence), fmt)
                    )
                    if fmt == "text":
                        texts.add(out)
        # Each flag combination must change the output, or equality proves
        # nothing about regrouping and silence handling.
        self.assertEqual(len(texts), 4)

    def test_unusable_input_is_a_usage_error(self):
        bad_word = live_result(0.6, False)
        bad_word["segments"][0]["words"][0]["start"] = "0.0"
        estimate = {"source": "talk.mp4", "duration_seconds": 9.0, "model": tr.MODEL}
        for name, content in [
            ("truncated", "{"),
            ("array", "[]"),
            ("estimate output", json.dumps(estimate)),
            ("string timing", json.dumps(bad_word)),
        ]:
            with self.subTest(name):
                path = self.dir / "bad.json"
                path.write_text(content, encoding="utf-8")
                self.assertEqual(
                    run_main(["--from-json", str(path)])[0], tr.EXIT_USAGE
                )
        missing = str(self.dir / "missing.json")
        self.assertEqual(run_main(["--from-json", missing])[0], tr.EXIT_USAGE)

    def test_api_only_flags_are_rejected(self):
        for flag in (
            ["--estimate"], ["--language", "en"], ["--context", "x"],
            ["--silence-db", "auto"],
        ):
            with self.subTest(flag=flag), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    tr.parse_args(["--from-json", "talk.json", *flag])
                self.assertEqual(caught.exception.code, tr.EXIT_USAGE)


class SilenceFlagTest(unittest.TestCase):
    def test_values(self):
        self.assertEqual(tr.parse_args(["a.mp4"]).silence_db, "auto")
        self.assertEqual(tr.parse_args(["a.mp4", "--silence-db", "auto"]).silence_db, "auto")
        self.assertEqual(tr.parse_args(["a.mp4", "--silence-db", "-32.5"]).silence_db, -32.5)
        for bad in ("loud", "0", "6", "nan", "-inf"):
            with self.subTest(bad), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    tr.parse_args(["a.mp4", f"--silence-db={bad}"])
                self.assertEqual(caught.exception.code, tr.EXIT_USAGE)


if __name__ == "__main__":
    unittest.main()
