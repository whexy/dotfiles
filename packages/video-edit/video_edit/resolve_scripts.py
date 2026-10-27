"""Python that runs inside DaVinci Resolve through the MCP `run_script_unsafe`.

Rules every generated script follows, from the 2026-10-13 session on
Resolve Studio 21.1:
- the source is ASCII and the result is `json.dumps(..., ensure_ascii=True)`
  in `result`: returning CJK strings raised UnicodeEncodeError (surrogates);
- `resolve` and `project` are injected globals, passed into `_main` so the
  script also works when exec'd from a one-liner;
- no per-item loops over timeline items: `GetItemListInTrack` alone took
  52 s on a 265-item track against the 60 s call cap, so builds make one
  `AppendToTimeline` call per track (one call placed 265 clips);
- `recordFrame` is absolute (`GetStartFrame()` + offset) and `endFrame` is
  `src_out`; see timeline.py for the frame convention;
- media-pool items are found by `File Path` in one folder walk;
- scripts only create timelines; they never modify an existing one.
"""

PRELUDE = '''\
import json


def _norm(path):
    return (path or "").replace("/", "\\\\").rstrip("\\\\").lower()


def _timelines(project):
    return [project.GetTimelineByIndex(i) for i in range(1, project.GetTimelineCount() + 1)]


def _setting(obj, key):
    try:
        value = obj.GetSetting(key)
    except Exception:
        value = None
    if value in (None, ""):
        try:
            value = (obj.GetSettings() or {}).get(key)
        except Exception:
            pass
    return value


def _find_clips(mp, paths):
    want = set(_norm(p) for p in paths)
    found = {}
    stack = [mp.GetRootFolder()]
    while stack and len(found) < len(want):
        folder = stack.pop()
        for clip in folder.GetClipList() or []:
            key = _norm(clip.GetClipProperty("File Path"))
            if key in want and key not in found:
                found[key] = clip
        stack.extend(folder.GetSubFolderList() or [])
    return found


def _import(mp, folder, paths):
    found = _find_clips(mp, paths)
    missing = [p for p in paths if _norm(p) not in found]
    if missing:
        mp.SetCurrentFolder(folder)
        for clip in mp.ImportMedia(missing) or []:
            found[_norm(clip.GetClipProperty("File Path"))] = clip
    absent = [p for p in paths if _norm(p) not in found]
    if absent:
        raise RuntimeError("could not import %s" % absent)
    return found, missing


def _subfolder(mp, parent, name):
    for folder in parent.GetSubFolderList() or []:
        if folder.GetName() == name:
            return folder
    return mp.AddSubFolder(parent, name)


def _new_timeline(project, mp, name):
    if name in [t.GetName() for t in _timelines(project)]:
        raise RuntimeError("timeline %s already exists" % name)
    mp.SetCurrentFolder(mp.GetRootFolder())
    tl = mp.CreateEmptyTimeline(name)
    if not tl or tl.GetName() != name:
        raise RuntimeError("CreateEmptyTimeline failed for %s" % name)
    project.SetCurrentTimeline(tl)
    current = project.GetCurrentTimeline()
    if not current or current.GetName() != name:
        raise RuntimeError("could not make %s the current timeline" % name)
    return tl
'''

EPILOGUE = '''

try:
    result = json.dumps(_main(resolve, project), ensure_ascii=True)
except Exception as exc:
    result = json.dumps({"ok": False, "error": "%s: %s" % (type(exc).__name__, exc)}, ensure_ascii=True)
'''

SYNC_MAIN = '''

def _main(resolve, project):
    names = set(t.GetName() for t in _timelines(project))
    name, n = NAME, 2
    while name in names:
        name, n = "%s %d" % (NAME, n), n + 1
    mp = project.GetMediaPool()
    clips, imported = _import(mp, mp.GetRootFolder(), [MAIN, CAMERA])
    tl = _new_timeline(project, mp, name)
    while tl.GetTrackCount("video") < 2:
        tl.AddTrack("video")
    while tl.GetTrackCount("audio") < 2:
        tl.AddTrack("audio", "stereo")
    base = tl.GetStartFrame()
    items = mp.AppendToTimeline([
        {"mediaPoolItem": clips[_norm(MAIN)], "trackIndex": 1, "recordFrame": base},
        {"mediaPoolItem": clips[_norm(CAMERA)], "trackIndex": 2, "recordFrame": base},
    ]) or []
    every = {}
    for item in items:
        every[item.GetUniqueId()] = item
        for linked in item.GetLinkedItems() or []:
            every[linked.GetUniqueId()] = linked
    aligned = tl.AutoAlignClips(
        list(every.values()), {"SyncUsing": resolve.AUTO_ALIGN_CLIPS_USING_WAVEFORM}
    )
    v1 = tl.GetItemListInTrack("video", 1) or []
    v2 = tl.GetItemListInTrack("video", 2) or []
    if len(v1) != 1 or len(v2) != 1:
        raise RuntimeError("expected one clip on V1 and V2, found %d and %d" % (len(v1), len(v2)))

    def where(item):
        return {
            "start": item.GetStart(),
            "left_offset": item.GetLeftOffset(),
            "source_start": item.GetSourceStartFrame(),
        }

    main, camera = where(v1[0]), where(v2[0])
    offset = (main["left_offset"] - main["start"]) - (camera["left_offset"] - camera["start"])
    return {
        "ok": bool(aligned),
        "timeline": name,
        "aligned": bool(aligned),
        "imported": len(imported),
        "main": main,
        "camera": camera,
        "camera_offset_frames": int(round(offset)),
        "derivation": "camera frame = main frame - N, "
        "N = (main.left_offset - main.start) - (camera.left_offset - camera.start)",
    }
'''

BUILD_MAIN = '''

def _main(resolve, project):
    fps = float(_setting(project, "timelineFrameRate") or 0)
    if abs(fps - FPS) > 1e-6:
        raise RuntimeError("project timeline frame rate is %s, the plan needs %s" % (fps, FPS))
    mp = project.GetMediaPool()
    root = mp.GetRootFolder()
    clips, imported = _import(mp, root, [MAIN] + ([CAMERA] if CAMERA else []))
    broll = {}
    if BROLL:
        found, more = _import(mp, _subfolder(mp, root, BROLL_BIN), list(BROLL.values()))
        broll = dict((slot, found[_norm(path)]) for slot, path in BROLL.items())
        imported += more
    tl = _new_timeline(project, mp, TIMELINE)
    while tl.GetTrackCount("video") < 3:
        if not tl.AddTrack("video"):
            raise RuntimeError("AddTrack(video) failed")
    for index, label in TRACK_NAMES:
        tl.SetTrackName("video", index, label)
    base = tl.GetStartFrame()
    appended = {}
    main = clips[_norm(MAIN)]
    appended["V1+A1"] = len(mp.AppendToTimeline([
        {"mediaPoolItem": main, "startFrame": a, "endFrame": b, "trackIndex": 1, "recordFrame": base + r}
        for a, b, r in V1
    ]) or [])
    if V2:
        camera = clips[_norm(CAMERA)]
        appended["V2"] = len(mp.AppendToTimeline([
            {"mediaPoolItem": camera, "startFrame": a, "endFrame": b, "trackIndex": 2,
             "recordFrame": base + r, "mediaType": 1}
            for a, b, r in V2
        ]) or [])
    if V3:
        appended["V3"] = len(mp.AppendToTimeline([
            {"mediaPoolItem": broll[slot], "trackIndex": 3, "recordFrame": base + r, "mediaType": 1}
            for slot, r in V3
        ]) or [])
    markers = 0
    for frame, color, name, note, duration, custom in MARKERS:
        if tl.AddMarker(frame, color, name, note, duration, custom):
            markers += 1
    tl.SetCurrentTimecode(tl.GetStartTimecode())
    end = tl.GetEndFrame()
    return {
        "ok": end == base + TOTAL,
        "timeline": TIMELINE,
        "start_frame": base,
        "start_timecode": tl.GetStartTimecode(),
        "end_frame": end,
        "expected_end_frame": base + TOTAL,
        "appended": appended,
        "planned": {"V1": len(V1), "V2": len(V2), "V3": len(V3)},
        "markers": [markers, len(MARKERS)],
        "imported": len(imported),
        "resolution": [_setting(tl, "timelineResolutionWidth"), _setting(tl, "timelineResolutionHeight")],
    }
'''

READBACK_MAIN = '''

def _main(resolve, project):
    import os

    matches = [t for t in _timelines(project) if t.GetName() == TIMELINE]
    if not matches:
        raise RuntimeError("no timeline named %s" % TIMELINE)
    tl = matches[0]
    ok = tl.Export(PATH, resolve.EXPORT_OTIO, resolve.EXPORT_NONE)
    return {
        "ok": bool(ok) and os.path.exists(PATH),
        "timeline": TIMELINE,
        "path": PATH,
        "bytes": os.path.getsize(PATH) if os.path.exists(PATH) else 0,
        "start_frame": tl.GetStartFrame(),
        "end_frame": tl.GetEndFrame(),
        "start_timecode": tl.GetStartTimecode(),
        "tracks": {"video": tl.GetTrackCount("video"), "audio": tl.GetTrackCount("audio")},
    }
'''


def _assign(name, value):
    return f"{name} = {ascii(value)}\n"


def _assign_rows(name, rows):
    if not rows:
        return f"{name} = []\n"
    body = "".join(f"    {ascii(tuple(row))},\n" for row in rows)
    return f"{name} = [\n{body}]\n"


def _header(command, run_line):
    return (
        f"# Generated by `video-edit {command}`; regenerate instead of editing.\n"
        "# Run inside Resolve through run_script_unsafe with timeout=60:\n"
        f"#   {run_line}\n"
    )


def sync_script(name, main_path, camera_path, run_line):
    data = (
        _assign("NAME", f"{name} sources (synced)")
        + _assign("MAIN", main_path)
        + _assign("CAMERA", camera_path)
    )
    return _header("sync-script", run_line) + data + PRELUDE + SYNC_MAIN + EPILOGUE


def build_script(plan, paths, run_line):
    """`paths` maps "main", "camera" and slot ids to the paths Resolve opens."""
    tracks = plan["tracks"]
    v3 = [(item["slot"], item["rec_in"]) for item in tracks.get("V3", [])]
    data = (
        _assign("TIMELINE", plan["timeline"])
        + _assign("FPS", float(plan["fps"]))
        + _assign("TOTAL", plan["duration_frames"])
        + _assign("MAIN", paths["main"])
        + _assign("CAMERA", paths.get("camera") if tracks.get("V2") else None)
        + _assign("BROLL_BIN", f"{plan['name']} B-roll")
        + _assign("BROLL", {slot: paths[slot] for slot, _ in v3})
        + _assign("TRACK_NAMES", ((1, "Main"), (2, "Camera"), (3, "B-roll")))
        + _assign_rows(
            "V1", [(i["src_in"], i["src_out"], i["rec_in"]) for i in tracks["V1"]]
        )
        + _assign_rows(
            "V2",
            [(i["src_in"], i["src_out"], i["rec_in"]) for i in tracks.get("V2", [])],
        )
        + _assign_rows("V3", v3)
        + _assign_rows(
            "MARKERS",
            [
                (m["frame"], m["color"], m["name"], m["note"], m["duration"], m["custom"])
                for m in plan["markers"]
            ],
        )
    )
    return (
        _header(f"build v{plan['version']}", run_line)
        + data
        + PRELUDE
        + BUILD_MAIN
        + EPILOGUE
    )


def readback_script(plan, otio_path, run_line):
    data = _assign("TIMELINE", plan["timeline"]) + _assign("PATH", otio_path)
    return (
        _header(f"readback-script v{plan['version']}", run_line)
        + data
        + PRELUDE
        + READBACK_MAIN
        + EPILOGUE
    )
