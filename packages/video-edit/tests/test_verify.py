import copy
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock
import wave

from tests import helpers
from video_edit import build, verify
from video_edit.common import NoKeyError, read_json, write_json

FIXTURE = Path(__file__).parent / "fixtures" / "readback_v1.otio"


class OtioTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.edit = helpers.EditRoot()
        build.run_build(cls.edit.root)
        cls.plan = cls.edit.root.plan(1)
        cls.data = json.loads(FIXTURE.read_text())

    @classmethod
    def tearDownClass(cls):
        cls.edit.close()

    def parse(self, data=None):
        return verify.parse_otio(data or self.data, 60)

    def problems(self, data):
        return verify.diff_plan(self.plan, self.parse(data))["problems"]

    def children(self, data, n):
        return data["tracks"]["children"][n]["children"]

    def test_parse(self):
        rb = self.parse()
        self.assertEqual(rb["global_start"], 216000)
        self.assertEqual(sorted(rb["tracks"]), ["A1", "V1", "V2", "V3"])
        v1 = rb["tracks"]["V1"]
        self.assertEqual(
            [(i["file"], i["src_in"], i["src_out"], i["rec_in"]) for i in v1],
            [("main.mkv", 55, 117, 0), ("main.mkv", 193, 285, 62), ("main.mkv", 319, 393, 154)],
        )
        self.assertEqual(rb["tracks"]["V2"][0]["src_in"], 40)  # Clip.1 media_reference
        self.assertEqual(rb["tracks"]["V3"][0]["kind"], "gap")
        self.assertEqual(rb["markers"], [82])

    def test_matching_readback_is_ok(self):
        report = verify.diff_plan(self.plan, self.parse())
        self.assertTrue(report["ok"], report)
        self.assertEqual(report["notes"], [])

    def test_other_rates_and_wrapping_collection(self):
        data = copy.deepcopy(self.data)
        clip = self.children(data, 0)[0]
        clip["source_range"]["start_time"] = {"OTIO_SCHEMA": "RationalTime.1", "rate": 120.0, "value": 110.0}
        clip["source_range"]["duration"] = {"OTIO_SCHEMA": "RationalTime.1", "rate": 120.0, "value": 124.0}
        wrapped = {"OTIO_SCHEMA": "SerializableCollection.1", "children": [data]}
        self.assertTrue(verify.diff_plan(self.plan, self.parse(wrapped))["ok"])

    def test_gap_shifts_everything_after_it(self):
        data = copy.deepcopy(self.data)
        gap = {"OTIO_SCHEMA": "Gap.1", "source_range": {"duration": {"rate": 60, "value": 1}}}
        self.children(data, 0).insert(1, gap)
        problems = self.problems(data)
        self.assertIn("V1: 1-frame gap at 62 (1.033s) where the plan has media", problems)
        self.assertTrue(any("V1 item 1" in p and "rec_in +1" in p for p in problems))
        self.assertTrue(any("timeline ends at frame 229" in p for p in problems))

    def test_off_by_one_length(self):
        data = copy.deepcopy(self.data)
        self.children(data, 0)[0]["source_range"]["duration"]["value"] = 61.0
        problems = self.problems(data)
        self.assertTrue(any("V1 item 0" in p and "length -1" in p for p in problems), problems)

    def test_wrong_source_and_wrong_track(self):
        data = copy.deepcopy(self.data)
        self.children(data, 0)[3]["media_references"]["DEFAULT_MEDIA"]["target_url"] = "file:///D:/Records/cam.mkv"
        moved = self.children(data, 1).pop(0)
        self.children(data, 2)[:] = [moved, {"OTIO_SCHEMA": "Gap.1", "source_range": {"duration": {"rate": 60, "value": 166}}}]
        problems = self.problems(data)
        self.assertTrue(any("V1 item 2" in p and "source cam.mkv" in p for p in problems), problems)
        self.assertTrue(any(p.startswith("V2: missing cam.mkv src 40-102") for p in problems), problems)
        self.assertTrue(any("V3: unexpected cam.mkv" in p and "belongs on V2" in p for p in problems), problems)

    def test_missing_track_and_start_note(self):
        data = copy.deepcopy(self.data)
        del data["tracks"]["children"][1]
        data["global_start_time"]["value"] = 0
        report = verify.diff_plan(self.plan, self.parse(data))
        self.assertFalse(report["ok"])
        self.assertTrue(any("srt --start-tc" in n for n in report["notes"]))

    def test_run_verify_timeline(self):
        target = self.edit.root / "verify" / "readback_v1.otio"
        target.write_text(FIXTURE.read_text())
        code, payload = verify.run_verify_timeline(self.edit.root, 1)
        self.assertEqual(code, 0, payload)


def ramp_wav(path, seconds, rate=16000):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join((i % 30000).to_bytes(2, "little") for i in range(int(seconds * rate))))


def samples(path):
    with wave.open(str(path), "rb") as w:
        data = w.readframes(w.getnframes())
    return [int.from_bytes(data[i : i + 2], "little") for i in range(0, len(data), 2)]


class AudioTest(unittest.TestCase):
    def setUp(self):
        self.edit = helpers.EditRoot()
        self.root = self.edit.root
        build.run_build(self.root)
        self.plan = self.root.plan(1)
        main = Path(read_json(self.root.sources_path)["main"]["path"])
        self.wav = self.root / "transcripts" / "main.16k.wav"
        ramp_wav(self.wav, helpers.DURATION)
        st = main.stat()
        write_json(self.wav.with_suffix(".json"), {"source": str(main), "size": st.st_size, "mtime_ns": st.st_mtime_ns})

    def tearDown(self):
        self.edit.close()

    def test_assembled_audio_is_sample_exact(self):
        out = self.edit.tmp / "cut.wav"
        verify.assemble_audio(self.wav, self.plan, out)
        got = samples(out)
        self.assertEqual(len(got), round(228 * 16000 / 60))
        # range 1 starts at source frame 193 and record frame 62
        rec = round(62 * 16000 / 60)
        self.assertEqual(got[rec], round(193 * 16000 / 60) % 30000)
        self.assertEqual(got[0], round(55 * 16000 / 60) % 30000)

    def fake_transcribe(self, body):
        bindir = Path(tempfile.mkdtemp(dir=self.edit.tmp))
        exe = bindir / "transcribe"
        exe.write_text(f"#!{sys.executable}\nimport sys, json, shutil\n{body}\n")
        exe.chmod(exe.stat().st_mode | stat.S_IEXEC)
        return mock.patch.dict(os.environ, {"PATH": f"{bindir}{os.pathsep}{os.environ['PATH']}"})

    def test_missing_key_is_exit_5(self):
        with self.fake_transcribe("sys.exit(5)"):
            with self.assertRaises(NoKeyError) as ctx:
                verify.run_verify_audio(self.root)
        self.assertEqual(ctx.exception.exit_code, 5)
        self.assertTrue((self.root / "verify" / "audio_v1.wav").exists())

    def test_clipped_word_is_tied_to_its_cut_and_cached(self):
        heard = helpers.transcript_json()
        # Drop "今" (first word after cut 1); shift words onto the output clock.
        kept = [w for w in heard["segments"][0]["words"] if w["word"] not in ("嗯", "今")]
        heard["segments"][0]["words"] = kept
        path = self.edit.tmp / "heard.json"
        path.write_text(json.dumps(heard, ensure_ascii=False), encoding="utf-8")
        script = f"out = sys.argv[sys.argv.index('-o') + 1]\nshutil.copyfile({str(path)!r}, out)"
        with self.fake_transcribe(script):
            code, payload = verify.run_verify_audio(self.root)
        self.assertEqual(code, 1)
        self.assertEqual(payload["flagged_cuts"][0]["cut"], 1)
        self.assertIn("clipped: expected '今'", payload["flagged_cuts"][0]["issues"][0])
        self.assertIn("strip --cut 1", payload["flagged_cuts"][0]["look"])
        with self.fake_transcribe("sys.exit(9)"):
            code, payload = verify.run_verify_audio(self.root)
        self.assertTrue(payload["cached"])


def word(text, start):
    return {"word": text, "start": start, "end": start + 0.1, "out_start": start, "out_end": start + 0.1}


class SpeechDiffTest(unittest.TestCase):
    EXPECTED = [word(c, 0.1 * i) for i, c in enumerate("大家好今天讲")] + [word("kubernetes", 0.6)]

    def test_pieces_join_and_case_is_ignored(self):
        heard = [word(c, 0.1 * i) for i, c in enumerate("大家好今天讲")] + [word("K", 0.6), word("ubernetes", 0.65)]
        issues, repeats, ratio = verify.diff_speech(self.EXPECTED, heard, [0.3])
        self.assertEqual(issues, [])
        self.assertEqual(ratio, 1.0)

    def test_repeats_are_tolerated_both_ways(self):
        heard = [word(c, 0.1 * i) for i, c in enumerate("大家家好今天讲kubernetes")]
        issues, repeats, _ = verify.diff_speech(self.EXPECTED, heard, [0.3])
        self.assertEqual((issues, repeats), ([], 1))
        expected = [word(c, 0.1 * i) for i, c in enumerate("我我觉得")]
        heard = [word(c, 0.1 * i) for i, c in enumerate("我觉得")]
        issues, repeats, _ = verify.diff_speech(expected, heard, [0.2])
        self.assertEqual((issues, repeats), ([], 1))

    def test_far_variants_are_not_flagged(self):
        heard = [word(c, 0.1 * i) for i, c in enumerate("大家好今天将")] + [word("kubernetes", 0.6)]
        issues, _, _ = verify.diff_speech(self.EXPECTED, heard, [5.0])
        self.assertEqual([(i["kind"], i["at_cut"]) for i in issues], [("variant", False)])

    def test_leaked_speech_at_a_cut(self):
        heard = [word(c, 0.1 * i) for i, c in enumerate("大家好嗯今天讲")] + [word("kubernetes", 0.7)]
        issues, _, _ = verify.diff_speech(self.EXPECTED, heard, [0.3])
        self.assertEqual([(i["kind"], i["heard"], i["cut"]) for i in issues], [("leaked", "嗯", 1)])


if __name__ == "__main__":
    unittest.main()
