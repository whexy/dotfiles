import os
from pathlib import Path
import shutil
import subprocess
import unittest
from unittest import mock

from tests import helpers
from video_edit import encode, slots
from video_edit.common import read_json, write_json
from video_edit.media import probe_video
from video_edit.project import default_spec

HAVE_FFMPEG = shutil.which("ffmpeg") is not None
HAVE_MANIMGX = shutil.which("manimgx") is not None
PATCHES = [(200, 40, 40), (40, 200, 60), (40, 60, 200), (128, 128, 128), (14, 15, 17), (251, 191, 36)]
W, H = 320, 180
# Max per-channel error after finalize. The conversion alone measured 2;
# the lossy libx265 stand-in adds a few; reading BT.601 as BT.709 is ~25.
TOLERANCE = 6


# The colour patches side by side under a dot that moves for half the clip,
# then holds still.
MANIMGX_SCENE = """
import manimgx as m


class Patches(m.Scene):
    def construct(self) -> None:
        patches = {patches!r}
        width = m.config.frame_width / len(patches)
        for i, colour in enumerate(patches):
            x = (i + 0.5) * width - m.config.frame_width / 2
            self.add(m.Rectangle(
                width=width, height=m.config.frame_height, fill_color=colour,
                fill_opacity=1, stroke_width=0,
            ).move_to(m.RIGHT * x))
        dot = m.Dot(m.UP * 3.5 + m.LEFT * 6, color=m.WHITE)
        self.play(dot.animate.shift(m.RIGHT * 12), run_time={move})
        self.wait({hold})
"""


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", *args], check=True)


def patch_rgb(path):
    pw = W // len(PATCHES)
    row = b"".join(bytes(PATCHES[min(x // pw, len(PATCHES) - 1)]) for x in range(W))
    path.write_bytes(row * H)


def measure(path, matrix="bt709"):
    """RGB at each patch centre of the first frame, decoding with `matrix`."""
    data = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-frames:v", "1", "-vf",
         f"scale=in_color_matrix={matrix}:in_range=tv,format=rgb24", "-f", "rawvideo", "-"],
        capture_output=True, check=True,
    ).stdout
    pw = W // len(PATCHES)
    out = []
    for i in range(len(PATCHES)):
        o = ((H // 2) * W + i * pw + pw // 2) * 3
        out.append(tuple(data[o : o + 3]))
    return out


def error(measured):
    return max(abs(a - b) for m, p in zip(measured, PATCHES) for a, b in zip(m, p))


class ColourDecisionTest(unittest.TestCase):
    def info(self, **kw):
        base = {"rgb": False, "pix_fmt": "yuv420p", "color_space": None, "color_range": None, "width": W, "height": H}
        return {**base, **kw}

    def test_matrix_decisions(self):
        cases = [
            (self.info(), "bt601", "untagged"),
            (self.info(color_space="unknown"), "bt601", "untagged"),
            (self.info(color_space="bt709"), "bt709", "from tag"),
            (self.info(color_space="bt470bg"), "bt601", "from tag"),
            (self.info(color_space="smpte170m"), "bt601", "from tag"),
        ]
        for info, matrix, note in cases:
            colour = encode.colour_input(info)
            self.assertEqual(colour["matrix"], matrix)
            self.assertIn(note, colour["notes"][0])
        self.assertEqual(encode.colour_input(self.info(color_space="bt709"), "bt601")["matrix"], "bt601")
        with self.assertRaises(Exception):
            encode.colour_input(self.info(color_space="bt2020nc"))
        self.assertEqual(encode.colour_input(self.info(rgb=True, pix_fmt="rgb24"))["kind"], "rgb")

    def test_range_and_kind(self):
        self.assertEqual(encode.colour_input(self.info(color_range="pc"))["range"], "pc")
        self.assertEqual(encode.colour_input(self.info(pix_fmt="yuvj420p"))["range"], "pc")
        self.assertEqual(encode.colour_input(self.info(pix_fmt="yuv420p10le"))["kind"], "yuv")
        self.assertEqual(encode.colour_input(self.info(pix_fmt="nv12"))["kind"], "yuv-scale")

    def test_filter_graph(self):
        colour = encode.colour_input(self.info())
        vf = encode.filter_graph(colour, self.info(), W, H, 60, 60, 0)
        self.assertTrue(vf.startswith("colorspace=ispace=bt470bg:irange=tv:"))
        self.assertNotIn("scale=", vf)
        self.assertTrue(vf.endswith("colorspace=bt709:range=tv"))
        vf = encode.filter_graph(colour, self.info(width=1920, height=1080), 3840, 2160, 60, 30, 2)
        self.assertIn("scale=3840:2160", vf)
        self.assertIn("fps=60", vf)
        self.assertIn("tpad=stop_mode=clone:stop=2", vf)

    def test_encode_args(self):
        spec = default_spec("x", {"width": 3840, "height": 2160, "fps": 60})
        args = encode.encode_args(spec, 60, 600, "hevc_nvenc")
        joined = " ".join(args)
        for part in ("-c:v hevc_nvenc", "-cq 16", "-g 60", "-frames:v 600", "-tag:v hvc1",
                     "-color_primaries bt709", "-color_trc bt709", "-colorspace bt709", "-fps_mode cfr"):
            self.assertIn(part, joined)
        self.assertIn("libx265", encode.encode_args(spec, 60, 600, "libx265"))


class TextFindingsTest(unittest.TestCase):
    def test_heuristics(self):
        import tempfile

        src = Path(tempfile.mkdtemp()) / "src"
        src.mkdir()
        (src / "a.html").write_text(
            "<div class='x'>Hello</div>\n<div>OpenAI</div>\n<script>el.textContent = 'Hi';</script>\n"
            "<style>.a::after { content: ''; }</style>\n<!-- 注释 -->\n",
            encoding="utf-8",
        )
        (src / "scene.py").write_text('t = Text("cost")\nc = Circle()\n', encoding="utf-8")
        (src / "ok.js").write_text("const x = 1; // no text here\n", encoding="utf-8")
        (src / "data.json").write_text('{"label": "ignored"}', encoding="utf-8")
        (src / "brand.html").write_text("<div>微信</div>\n", encoding="utf-8")
        findings = encode.text_findings(src, ["OpenAI", "微信"])
        joined = "\n".join(findings)
        self.assertIn("a.html:1: visible text 'Hello'", joined)
        self.assertIn("visible text 'Hi'", joined)
        self.assertIn("a.html:5: CJK characters", joined)
        self.assertIn("scene.py:1: visible text 'cost'", joined)
        self.assertNotIn("OpenAI", joined)
        self.assertNotIn("brand.html", joined)
        self.assertNotIn("ok.js", joined)
        self.assertNotIn("data.json", joined)
        shutil.rmtree(src.parent)


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg")
class FinalizeTest(unittest.TestCase):
    def setUp(self):
        self.edit = helpers.EditRoot()
        self.root = self.edit.root
        spec = read_json(self.root.spec_path)
        spec["timeline"].update(width=W, height=H)
        spec["draft"].update(width=W // 2, height=H // 2)
        write_json(self.root.spec_path, spec)
        slots.run_slots(self.root)
        self.slot_dir = self.root / "slots" / "G1"
        self.slot = read_json(self.slot_dir / "slot.json")
        self.rgb = self.edit.tmp / "patch.rgb"
        patch_rgb(self.rgb)
        # libx265 stands in for NVENC, which the build sandbox lacks.
        self.env = mock.patch.dict(os.environ, {"VIDEO_EDIT_ENCODER": "libx265"})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.edit.close()

    def raw(self, name, frames, matrix="bt601", tags=(), fps=60, size=(W, H)):
        """A raw render of the colour patches, untagged BT.601 like plain libx264."""
        tagged = self.edit.tmp / f"{name}.tagged.mp4"
        ffmpeg(
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(fps), "-i", str(self.rgb),
            "-vf", f"loop=loop={frames - 1}:size=1:start=0,scale={size[0]}:{size[1]}:out_color_matrix={matrix}:out_range=tv,format=yuv420p",
            "-frames:v", str(frames), "-c:v", "libx264", "-qp", "0", *tags, str(tagged),
        )
        if tags:
            return tagged
        out = self.edit.tmp / f"{name}.mp4"
        ffmpeg("-i", str(tagged), "-c", "copy", "-bsf:v",
               "h264_metadata=matrix_coefficients=2:colour_primaries=2:transfer_characteristics=2",
               str(out))
        return out

    def test_untagged_bt601(self):
        raw = self.raw("untagged", 120)
        info = probe_video(raw, count=None)
        self.assertEqual(info["color_space"], None)
        self.assertGreater(error(measure(raw, "bt709")), 15)  # the shift a naive pass keeps
        code, payload = encode.run_finalize(self.root, raw, self.slot_dir)
        self.assertEqual(code, 0, payload)
        self.assertIn("untagged", payload["notes"][0])
        out = self.root / payload["out"]
        self.assertEqual(out.name, "G1_v1.mp4")
        self.assertLessEqual(error(measure(out, "bt709")), TOLERANCE)
        code, report = encode.run_check(self.root, out, self.slot_dir)
        self.assertEqual(code, 1)
        # Everything passes except the CPU encoder standing in for NVENC.
        self.assertEqual(len(report["problems"]), 1, report)
        self.assertIn("libx265 on the CPU", report["problems"][0])
        self.assertEqual(report["probe"]["frames"], 120)
        self.assertEqual(report["probe"]["color_range"], "tv")
        self.assertTrue((self.root / report["sheet"]).exists())
        record = read_json(out.with_suffix(".check.json"))
        self.assertEqual((record["pass"], record["signature"]), (False, self.slot["signature"]))
        # never overwrite: the next finalize is v2
        code, payload = encode.run_finalize(self.root, raw, self.slot_dir)
        self.assertEqual(Path(payload["out"]).name, "G1_v2.mp4")

    def test_hyperframes_style_matrix_tag_only(self):
        raw = self.raw("hf", 120, matrix="bt709", tags=("-colorspace", "bt709"))
        info = probe_video(raw, count=None)
        self.assertEqual((info["color_space"], info["color_primaries"]), ("bt709", None))
        code, payload = encode.run_finalize(self.root, raw, self.slot_dir)
        self.assertEqual(code, 0, payload)
        self.assertIn("from tag bt709", payload["notes"][0])
        self.assertLessEqual(error(measure(self.root / payload["out"], "bt709")), TOLERANCE)

    @unittest.skipUnless(HAVE_MANIMGX, "needs manimgx")
    def test_manimgx_holds_and_closing_frame(self):
        scene = self.slot_dir / "src" / "scene.py"
        patches = ["#%02x%02x%02x" % p for p in PATCHES]
        half = self.slot["duration"] / 2
        draft = self.slot["draft"]

        def render(name, want, hold):
            scene.write_text(MANIMGX_SCENE.format(patches=patches, move=half, hold=hold))
            out = self.slot_dir / name / "G1.mp4"
            subprocess.run(
                ["manimgx", "render", str(scene), "-r", f"{want['width']}x{want['height']}",
                 "--fps", str(want["fps"]), "-o", str(out)],
                check=True, capture_output=True,
            )
            return out

        code, report = encode.run_check(
            self.root, render("draft", draft, half), self.slot_dir, draft=True
        )
        self.assertEqual(code, 0, report)
        # The held half is one sample, so far fewer frames decode than show.
        self.assertLess(report["probe"]["frames"], draft["frames"] * 3 // 4)
        code, payload = encode.run_finalize(
            self.root, render("render", self.slot, half), self.slot_dir
        )
        self.assertEqual(code, 0, payload)
        self.assertEqual(payload["input"]["frames"], self.slot["frames"])
        self.assertEqual(payload["notes"], ["matrix from tag smpte170m"])
        out = self.root / payload["out"]
        self.assertEqual(probe_video(out)["frames"], self.slot["frames"])
        self.assertLessEqual(error(measure(out, "bt709")), TOLERANCE)
        # A scene one frame short of the clip fails the draft check.
        short = render("draft", draft, half - 1 / draft["fps"])
        code, report = encode.run_check(self.root, short, self.slot_dir, draft=True)
        self.assertIn(f"{draft['frames'] - 1} frames, want {draft['frames']}", report["problems"])

    def test_frame_count_fitting(self):
        code, payload = encode.run_finalize(self.root, self.raw("short", 119), self.slot_dir)
        self.assertEqual(code, 0, payload)
        self.assertIn("last frame held for 1 frame(s)", payload["notes"])
        self.assertEqual(probe_video(self.root / payload["out"])["frames"], 120)
        code, payload = encode.run_finalize(self.root, self.raw("wrong", 100), self.slot_dir)
        self.assertEqual(code, 1)
        self.assertIn("needs exactly 120", payload["errors"][0])

    def test_dry_run_uses_nvenc_by_default(self):
        self.env.stop()
        try:
            code, payload = encode.run_finalize(self.root, self.raw("dry", 120), self.slot_dir, dry_run=True)
        finally:
            self.env.start()
        self.assertEqual(code, 0)
        self.assertIn("hevc_nvenc", payload["command"])
        self.assertEqual(list((self.slot_dir / "out").glob("*.mp4")), [])

    def test_check_draft(self):
        frames = self.slot["draft"]["frames"]
        draft = self.edit.tmp / "draft.mp4"
        ffmpeg("-f", "lavfi", "-i", f"testsrc2=s={W // 2}x{H // 2}:r=30", "-frames:v", str(frames),
               "-c:v", "libx264", "-pix_fmt", "yuv420p", str(draft))
        code, report = encode.run_check(self.root, draft, self.slot_dir, draft=True)
        self.assertEqual(code, 0, report)
        short = self.edit.tmp / "short.mp4"
        ffmpeg("-i", str(draft), "-frames:v", str(frames - 1), "-c:v", "libx264", str(short))
        code, report = encode.run_check(self.root, short, self.slot_dir, draft=True)
        self.assertIn(f"{frames - 1} frames, want {frames}", report["problems"])

    def test_alpha_and_text_fail_the_check(self):
        alpha = self.edit.tmp / "alpha.mkv"
        ffmpeg("-f", "lavfi", "-i", f"testsrc2=s={W // 2}x{H // 2}:r=30", "-frames:v", str(self.slot["draft"]["frames"]),
               "-vf", "format=yuva420p", "-c:v", "ffv1", str(alpha))
        (self.slot_dir / "src" / "index.html").write_text("<p>标题</p>\n", encoding="utf-8")
        code, report = encode.run_check(self.root, alpha, self.slot_dir, draft=True)
        self.assertEqual(code, 1)
        problems = "\n".join(report["problems"])
        self.assertIn("has alpha (yuva420p)", problems)
        self.assertIn("CJK characters", problems)
        self.assertIn("visible text '标题'", problems)
        self.assertTrue((self.root / report["sheet"]).exists())


if __name__ == "__main__":
    unittest.main()
