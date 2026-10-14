import json
import os
import unittest

from tests import fake_resolve, helpers
from video_edit import build, resolve_scripts, slots
from video_edit.common import UsageError, exec_line, read_json, write_json
from video_edit.slots import check_record


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.edit = helpers.EditRoot()
        self.root = self.edit.root

    def tearDown(self):
        self.edit.close()

    def build(self, **kwargs):
        code, payload = build.run_build(self.root, **kwargs)
        self.assertEqual(code, 0, payload)
        return payload, read_json(self.root / payload["plan"])

    def test_plan_tracks(self):
        payload, plan = self.build()
        self.assertEqual(payload["timeline"], "Demo agent v1")
        v1 = [(i["src_in"], i["src_out"], i["rec_in"], i["rec_out"]) for i in plan["tracks"]["V1"]]
        self.assertEqual(v1, [(55, 117, 0, 62), (193, 285, 62, 154), (319, 393, 154, 228)])
        self.assertEqual(plan["tracks"]["A1"], plan["tracks"]["V1"])
        # camera frame = main frame - 15
        self.assertEqual(plan["tracks"]["V2"][0]["src_in"], 40)
        self.assertEqual(plan["tracks"]["V3"], [])
        self.assertEqual(plan["markers"][0]["color"], "Red")
        self.assertEqual(payload["broll"]["pending"], {"G1": "no finalized output yet"})

    def test_versions_are_never_rebuilt(self):
        self.build()
        payload, _ = self.build()
        self.assertEqual(payload["version"], 2)
        with self.assertRaises(UsageError):
            build.run_build(self.root, version=1)

    def test_section_build(self):
        payload, plan = self.build(section="S02")
        self.assertEqual(payload["timeline"], "Demo S02 agent v1")
        self.assertEqual(plan["tracks"]["V1"][0]["rec_in"], 0)
        self.assertEqual(plan["duration_frames"], 74)
        with self.assertRaises(UsageError):
            build.run_build(self.root, section="S09")

    def test_invalid_edl_writes_nothing(self):
        edl = helpers.default_edl()
        edl["ranges"][0]["start"] = 59 / helpers.FPS  # 17 ms before speech
        self.edit.write_edl(edl)
        code, payload = build.run_build(self.root)
        self.assertEqual(code, 1)
        self.assertTrue(payload["errors"])
        self.assertEqual(self.root.plan_versions(), [])

    def test_camera_offset_required(self):
        sources = read_json(self.root.sources_path)
        sources["camera"]["offset_frames"] = None
        write_json(self.root.sources_path, sources)
        with self.assertRaises(UsageError):
            build.run_build(self.root)
        payload, plan = self.build(no_camera=True)
        self.assertEqual(plan["tracks"]["V2"], [])

    def test_script_runs_against_fake_resolve(self):
        payload, plan = self.build()
        source = (self.root / payload["script"]).read_text(encoding="ascii")
        compile(source, "build_v1.py", "exec")
        project = fake_resolve.Project()
        result = json.loads(fake_resolve.run(source, project, self.edit.tmp / "build.py"))
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["end_frame"], 216000 + 228)
        v1_call, v2_call = project.pool.appends
        self.assertEqual(
            [(i["startFrame"], i["endFrame"], i["recordFrame"]) for i in v1_call],
            [(55, 117, 216000), (193, 285, 216062), (319, 393, 216154)],
        )
        self.assertNotIn("mediaType", v1_call[0])
        self.assertTrue(all(i["mediaType"] == 1 and i["trackIndex"] == 2 for i in v2_call))
        tl = project.timelines[0]
        self.assertEqual(tl.GetTrackCount("video"), 3)
        self.assertEqual(tl.markers[0][:3], (82, "Red", "G1"))

    def test_script_refuses_existing_timeline_and_wrong_fps(self):
        payload, _ = self.build()
        source = (self.root / payload["script"]).read_text(encoding="ascii")
        project = fake_resolve.Project()
        project.timelines.append(fake_resolve.Timeline("Demo agent v1"))
        result = json.loads(fake_resolve.run(source, project))
        self.assertFalse(result["ok"])
        self.assertIn("already exists", result["error"])
        result = json.loads(fake_resolve.run(source, fake_resolve.Project(fps="30")))
        self.assertIn("frame rate", result["error"])

    def test_passing_broll_is_placed(self):
        build.run_build(self.root)
        slots.run_slots(self.root)
        slot = read_json(self.root / "slots" / "G1" / "slot.json")
        out = self.root / "slots" / "G1" / "out" / "G1_v1.mp4"
        out.write_bytes(b"video")
        stat = out.stat()
        record = {"pass": True, "mode": "final", "signature": slot["signature"], "size": stat.st_size, "mtime_ns": stat.st_mtime_ns}
        write_json(check_record(out), record)
        payload, plan = self.build()
        self.assertEqual(payload["broll"]["placed"], ["G1"])
        self.assertEqual(plan["tracks"]["V3"][0]["rec_in"], 82)
        self.assertEqual(plan["tracks"]["V3"][0]["src_out"], 120)
        project = fake_resolve.Project(clip_frames={r"D:\Records\edit\Demo\slots\G1\out\G1_v1.mp4": 120})
        source = (self.root / payload["script"]).read_text(encoding="ascii")
        result = json.loads(fake_resolve.run(source, project))
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["appended"]["V3"], 1)
        self.assertEqual([f.GetName() for f in project.pool.root.subfolders], ["Demo B-roll"])

        # An earlier in-point moves G1 together with its speech: still valid.
        edl = helpers.default_edl()
        edl["ranges"][1]["start"] = 190 / helpers.FPS
        self.edit.write_edl(edl)
        payload, plan = self.build()
        self.assertEqual(plan["tracks"]["V3"][0]["rec_in"], 85)

        # A cut inside G1's window moves speech under it: the render is stale.
        edl["ranges"][2]["start"] = 316 / helpers.FPS
        self.edit.write_edl(edl)
        payload, plan = self.build()
        self.assertEqual(plan["tracks"]["V3"], [])
        self.assertIn("older slot definition", payload["broll"]["pending"]["G1"])

    def test_readback_script(self):
        self.build()
        code, payload = build.run_readback_script(self.root)
        self.assertEqual(code, 0)
        self.assertTrue(payload["run"].startswith("exec(open('D:\\\\Records"))
        plan = self.root.plan()
        target = str(self.edit.tmp / "readback.otio")
        source = resolve_scripts.readback_script(plan, target, "x")
        project = fake_resolve.Project()
        project.timelines.append(fake_resolve.Timeline("Demo agent v1"))
        result = json.loads(fake_resolve.run(source, project))
        self.assertTrue(result["ok"], result)
        self.assertEqual(project.timelines[0].exported[1:], (15.0, 0.0))


class ScriptTextTest(unittest.TestCase):
    def test_cjk_names_stay_ascii_in_scripts_and_results(self):
        plan = {
            "version": 1, "name": "工作流", "timeline": "工作流 agent v1", "fps": 60,
            "duration_frames": 10, "markers": [{"frame": 0, "color": "Red", "name": "G1", "note": "说明", "duration": 5, "custom": "c"}],
            "tracks": {"V1": [{"src_in": 0, "src_out": 10, "rec_in": 0}], "V2": [], "V3": []},
        }
        source = resolve_scripts.build_script(plan, {"main": "D:\\录制\\a.mkv"}, "x")
        source.encode("ascii")
        compile(source, "build.py", "exec")
        self.assertIn("result = json.dumps(_main(resolve, project), ensure_ascii=True)", source)
        project = fake_resolve.Project()
        result = fake_resolve.run(source, project)
        result.encode("ascii")
        self.assertEqual(project.timelines[0].GetName(), "工作流 agent v1")
        self.assertEqual(project.timelines[0].markers[0][3], "说明")

    def test_sync_script_reports_the_offset(self):
        source = resolve_scripts.sync_script("Demo", "D:\\a.mkv", "D:\\cam.mkv", "x")
        compile(source, "sync.py", "exec")
        project = fake_resolve.Project()
        project.timelines.append(fake_resolve.Timeline("Demo sources (synced)"))
        result = json.loads(fake_resolve.run(source, project))
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["timeline"], "Demo sources (synced) 2")
        self.assertEqual(result["camera_offset_frames"], 15)
        self.assertEqual(project.timelines[1].GetTrackCount("audio"), 2)

    def test_exec_line_escapes_the_path(self):
        line = exec_line("D:\\Records\\edit\\视频\\resolve\\build_v1.py")
        line.encode("ascii")
        self.assertEqual(
            eval(line[len("exec(open(") : line.index(", encoding")]),
            "D:\\Records\\edit\\视频\\resolve\\build_v1.py",
        )


class SlotsTest(unittest.TestCase):
    def setUp(self):
        self.edit = helpers.EditRoot()
        self.root = self.edit.root

    def tearDown(self):
        self.edit.close()

    def test_slot_json_maps_speech_across_cuts(self):
        code, payload = slots.run_slots(self.root)
        self.assertEqual(code, 0, payload)
        slot = read_json(self.root / "slots" / "G1" / "slot.json")
        self.assertEqual((slot["frames"], slot["fps"], slot["width"]), (120, 60, 3840))
        self.assertEqual(slot["duration"], 2.0)
        self.assertEqual(slot["timeline_offset_frames"], 82)
        self.assertEqual(slot["anchor"], {"t": 0.45, "frame": 27, "draft_frame": 14, "word": "ubernetes"})
        by_word = {b["word"]: b for b in slot["beats"]}
        # "然" is in the next range: 5 frames after its in-point, which is
        # record frame 154; the slot starts at record frame 82.
        self.assertEqual(by_word["然"]["frame"], 154 + 5 - 82)
        self.assertAlmostEqual(by_word["然"]["t"], (154 + 5 - 82) / 60, places=3)
        self.assertEqual(by_word["然"]["draft_frame"], 39)  # 38.5 rounds up
        self.assertNotIn("嗯", by_word)
        self.assertEqual(slot["voiceover"], "天讲kubernetes然后结束")
        self.assertEqual([p["text"] for p in slot["phrases"]], ["天讲kubernetes", "然后结束"])
        self.assertTrue(os.path.isdir(slot["paths"]["src"]))

    def test_brief_is_never_overwritten(self):
        slots.run_slots(self.root)
        brief = self.root / "slots" / "G1" / "brief.md"
        brief.write_text("mine")
        slots.run_slots(self.root)
        self.assertEqual(brief.read_text(), "mine")

    def test_draft_frames_follow_hyperframes_rounding(self):
        self.assertEqual(slots.draft_frames(241 / 60, 30), 121)
        self.assertEqual(slots.draft_frames(240 / 60, 30), 120)
        self.assertEqual(slots.draft_frames(361 / 60, 30), 181)

    def test_full_precision_duration(self):
        edl = helpers.default_edl()
        edl["overlays"][0]["duration"] = 121 / 60
        self.edit.write_edl(edl)
        slots.run_slots(self.root)
        slot = read_json(self.root / "slots" / "G1" / "slot.json")
        self.assertEqual(slot["frames"], 121)
        self.assertEqual(slot["duration"], 121 / 60)
        self.assertEqual(slot["draft"]["frames"], 61)

    def test_passing_output_rules(self):
        slots.run_slots(self.root)
        slot_dir = self.root / "slots" / "G1"
        sig = read_json(slot_dir / "slot.json")["signature"]
        self.assertEqual(slots.passing_output(slot_dir, "G1", sig), (None, "no finalized output yet"))
        good = slot_dir / "out" / "G1_v1.mp4"
        bad = slot_dir / "out" / "G1_v2.mp4"
        for path, ok in ((good, True), (bad, False)):
            path.write_bytes(b"x")
            st = path.stat()
            write_json(check_record(path), {"pass": ok, "mode": "final", "signature": sig, "size": st.st_size, "mtime_ns": st.st_mtime_ns})
        found, _ = slots.passing_output(slot_dir, "G1", sig)
        self.assertEqual(found, good)
        found, why = slots.passing_output(slot_dir, "G1", "other")
        self.assertIsNone(found)
        self.assertIn("older slot definition", why)


if __name__ == "__main__":
    unittest.main()
