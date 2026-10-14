"""init, silence detection, strip and the CLI, against small generated media."""

import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

from tests import helpers
from video_edit import build, cli, project, silence
from video_edit.common import Root, UsageError, mnt_to_windows, read_json, write_json

HAVE_FFMPEG = shutil.which("ffmpeg") is not None


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", *args], check=True)


def talk(path, seconds=8, size="320x180"):
    """testsrc2 video; a 440 Hz tone over a -50 dB noise bed, with the tone
    off at 1.7-2.5 s and 4.5-5.4 s."""
    gate = "between(t,1.7,2.5)+between(t,4.5,5.4)"
    ffmpeg(
        "-f", "lavfi", "-i", f"testsrc2=s={size}:r=60:d={seconds}",
        "-f", "lavfi", "-i", f"sine=f=440:d={seconds}:sample_rate=48000",
        "-f", "lavfi", "-i", f"anoisesrc=d={seconds}:c=white:r=48000:a=0.003:seed=1",
        "-filter_complex",
        f"[1]volume='if({gate},0,0.5)':eval=frame[t];[t][2]amix=inputs=2:normalize=0[a]",
        "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "ultrafast",
        "-c:a", "aac", "-shortest", str(path),
    )


class PathTest(unittest.TestCase):
    def test_mnt_paths(self):
        self.assertEqual(mnt_to_windows("/mnt/d/Records/a b.mkv"), "D:\\Records\\a b.mkv")
        self.assertEqual(mnt_to_windows("/mnt/c"), "C:\\")
        with self.assertRaises(UsageError):
            mnt_to_windows("/tmp/x")


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg")
class InitTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="video-edit-init-"))
        self.main = self.tmp / "Records" / "talk.mkv"
        self.main.parent.mkdir()
        talk(self.main)
        shutil.copyfile(self.main, self.tmp / "Records" / "cam.mkv")
        self.patch = mock.patch.object(project, "to_windows", lambda p: "D:\\" + Path(p).name)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_init_then_reinit_keeps_user_files(self):
        code, payload = project.run_init(self.main, self.tmp / "Records" / "cam.mkv", "AI 工作流")
        self.assertEqual(code, 0, payload)
        root = Root(payload["root"])
        self.assertEqual(root.path, self.tmp / "Records" / "edit" / "AI 工作流")
        sources = read_json(root.sources_path)
        self.assertEqual(
            (sources["main"]["fps"], sources["main"]["frames"], sources["main"]["has_audio"]),
            (60, 480, True),
        )
        self.assertIsNone(sources["camera"]["offset_frames"])
        spec = read_json(root.spec_path)
        self.assertEqual((spec["timeline"]["width"], spec["timeline"]["fps"]), (320, 60))
        self.assertFalse(spec["rules"]["text"])
        self.assertEqual(spec["subtitles"]["maxChars"], 17)
        self.assertIn("--bg: #0e0f11", (root / "style" / "tokens.css").read_text())
        self.assertIn("transcribe", payload["next"])
        self.assertNotIn("--context", payload["next"])

        spec["name"] = "edited"
        write_json(root.spec_path, spec)
        project.run_set_offset(root, 15)
        project.run_set_offset(root, 18, at=3.0)
        code, payload = project.run_init(self.main, self.tmp / "Records" / "cam.mkv", "AI 工作流")
        self.assertEqual(payload["created"], [])
        self.assertEqual(read_json(root.spec_path)["name"], "edited")
        camera = read_json(root.sources_path)["camera"]
        self.assertEqual((camera["offset_frames"], camera["offset_changes"]), (15, [{"at": 3.0, "offset_frames": 18}]))

    def test_silences_from_the_noise_floor(self):
        code, payload = project.run_init(self.main, None, "Demo")
        root = Root(payload["root"])
        data = silence.load(root, read_json(root.sources_path)["main"], read_json(root.spec_path))
        spans = data["silences"]
        self.assertTrue(data["threshold_from"].startswith("noise floor"), data)
        self.assertAlmostEqual(data["threshold_db"], data["noise_floor_db"] + 9, places=1)
        self.assertTrue(any(abs(s - 1.7) < 0.05 and abs(e - 2.5) < 0.05 for s, e in spans), spans)
        self.assertTrue(any(abs(s - 4.5) < 0.05 and abs(e - 5.4) < 0.05 for s, e in spans), spans)
        self.assertEqual(silence.load(root, read_json(root.sources_path)["main"], read_json(root.spec_path)), data)


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg")
class StripTest(unittest.TestCase):
    def setUp(self):
        self.edit = helpers.EditRoot()
        self.root = self.edit.root
        main = Path(read_json(self.root.sources_path)["main"]["path"])
        talk(main)
        # the silence cache is keyed to the file; re-key it to the real media
        cache = self.root / "transcripts" / "main.silences.json"
        data = read_json(cache)
        st = main.stat()
        data.update(size=st.st_size, mtime_ns=st.st_mtime_ns)
        write_json(cache, data)
        build.run_build(self.root)

    def tearDown(self):
        self.edit.close()

    def test_source_and_cut_strips(self):
        from video_edit import strip

        main = read_json(self.root.sources_path)["main"]["path"]
        cwd = os.getcwd()
        os.chdir(self.root.path)
        try:
            code, payload = strip.run_strip(main, 0.5, 3.5, n_frames=4)
            self.assertTrue(Path(payload["png"]).exists())
            code, payload = strip.run_strip(None, None, None, cut=1, around=1.0, n_frames=4)
            self.assertTrue((self.root / payload["png"]).exists())
            with self.assertRaises(UsageError):
                strip.run_strip(None, None, None, cut=9)
        finally:
            os.chdir(cwd)


class EnvelopeTest(unittest.TestCase):
    def test_bins_line_up_with_time(self):
        import numpy as np

        from video_edit.strip import envelope

        # 4 s at 16 kHz, loud from 1.8 s on, drawn 1900 px wide
        samples = np.zeros(64000, dtype=np.float32)
        samples[int(1.8 * 16000) :] = 0.5
        env = envelope(samples, 1900)
        self.assertEqual(env.size, 1900)
        first_loud = int(np.argmax(env > 0.5))
        self.assertAlmostEqual(first_loud / 1900 * 4.0, 1.8, delta=4.0 / 1900)


class CliTest(unittest.TestCase):
    def run_cli(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = cli.main(list(argv))
        return code, out.getvalue()

    def test_usage_errors_are_exit_2_with_json(self):
        code, out = self.run_cli("build", "--root", "/nonexistent")
        self.assertEqual(code, 2)
        self.assertFalse(json.loads(out)["ok"])

    @mock.patch("video_edit.common.to_windows", lambda p: "D:\\Records\\edit\\Demo")
    def test_build_and_words_through_the_cli(self):
        edit = helpers.EditRoot()
        try:
            code, out = self.run_cli("build", "--root", str(edit.root.path))
            self.assertEqual(code, 0, out)
            self.assertEqual(json.loads(out)["timeline"], "Demo agent v1")
            code, out = self.run_cli("words", "--root", str(edit.root.path))
            self.assertIn("今|天|讲", out)
            code, out = self.run_cli("set-offset", "-12", "--root", str(edit.root.path))
            self.assertEqual(json.loads(out)["offset_frames"], -12)
        finally:
            edit.close()


if __name__ == "__main__":
    unittest.main()
