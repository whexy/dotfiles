"""A small stand-in for Resolve's scripting objects, enough to run the
generated scripts: it records every AppendToTimeline call and places
items using endFrame - startFrame as the clip length."""

import os
import warnings


def _norm(path):
    return path.replace("/", "\\").lower()


class Clip:
    def __init__(self, path, frames=1000):
        self.path, self.frames = path, frames

    def GetClipProperty(self, key=None):
        return self.path if key == "File Path" else ""

    def GetName(self):
        return self.path.rsplit("\\", 1)[-1]


class Folder:
    def __init__(self, name):
        self.name, self.clips, self.subfolders = name, [], []

    def GetName(self):
        return self.name

    def GetClipList(self):
        return list(self.clips)

    def GetSubFolderList(self):
        return list(self.subfolders)


class Item:
    def __init__(self, timeline, clip, track_type, track, start, left, length):
        self.timeline, self.clip = timeline, clip
        self.track_type, self.track = track_type, track
        self.start, self.left, self.length = start, left, length
        self.uid = f"{track_type}{track}@{start}"

    def GetStart(self):
        return self.start

    def GetEnd(self):
        return self.start + self.length

    def GetLeftOffset(self):
        return self.left

    def GetSourceStartFrame(self):
        return self.left

    def GetUniqueId(self):
        return self.uid

    def GetLinkedItems(self):
        return [i for i in self.timeline.items if i.clip is self.clip and i is not self]


class Timeline:
    def __init__(self, name, start=216000):
        self.name, self.start = name, start
        self.tracks = {"video": 1, "audio": 1}
        self.items, self.markers, self.track_names = [], [], {}
        self.exported = None

    def GetName(self):
        return self.name

    def GetStartFrame(self):
        return self.start

    def GetEndFrame(self):
        return max([i.GetEnd() for i in self.items], default=self.start)

    def GetStartTimecode(self):
        return "01:00:00:00"

    def SetCurrentTimecode(self, tc):
        return True

    def GetTrackCount(self, kind):
        return self.tracks[kind]

    def AddTrack(self, kind, sub=None):
        self.tracks[kind] += 1
        return True

    def SetTrackName(self, kind, index, name):
        self.track_names[(kind, index)] = name
        return True

    def AddMarker(self, frame, color, name, note, duration, custom=None):
        self.markers.append((frame, color, name, note, duration, custom))
        return True

    def GetSetting(self, key):
        return {"timelineResolutionWidth": "3840", "timelineResolutionHeight": "2160"}.get(key)

    def GetItemListInTrack(self, kind, index):
        return [i for i in self.items if (i.track_type, i.track) == (kind, index)]

    def AutoAlignClips(self, items, options):
        self.align_options = options
        for item in items:
            if item.track == 2:
                item.start += 15
        return True

    def Export(self, path, kind, subtype):
        self.exported = (path, kind, subtype)
        with open(path, "w") as fh:
            fh.write("{}")
        return True


class MediaPool:
    def __init__(self, project):
        self.project = project
        self.root = Folder("Master")
        self.current = self.root
        self.appends = []

    def GetRootFolder(self):
        return self.root

    def SetCurrentFolder(self, folder):
        self.current = folder
        return True

    def AddSubFolder(self, parent, name):
        folder = Folder(name)
        parent.subfolders.append(folder)
        return folder

    def ImportMedia(self, paths):
        clips = [Clip(p, frames=self.project.clip_frames.get(_norm(p), 1000)) for p in paths]
        self.current.clips += clips
        return clips

    def CreateEmptyTimeline(self, name):
        tl = Timeline(name)
        self.project.timelines.append(tl)
        return tl

    def AppendToTimeline(self, infos):
        tl = self.project.current
        self.appends.append(infos)
        made = []
        for info in infos:
            clip = info["mediaPoolItem"]
            left = info.get("startFrame", 0)
            length = info["endFrame"] - left if "endFrame" in info else clip.frames
            kinds = {1: ["video"], 2: ["audio"]}.get(info.get("mediaType"), ["video", "audio"])
            for kind in kinds:
                start = info.get("recordFrame", tl.GetEndFrame())
                item = Item(tl, clip, kind, info.get("trackIndex", 1), start, left, length)
                tl.items.append(item)
                made.append(item)
        return made


class Project:
    def __init__(self, fps="60", clip_frames=None):
        self.timelines, self.current, self.fps = [], None, fps
        self.clip_frames = {_norm(k): v for k, v in (clip_frames or {}).items()}
        self.pool = MediaPool(self)

    def GetMediaPool(self):
        return self.pool

    def GetTimelineCount(self):
        return len(self.timelines)

    def GetTimelineByIndex(self, i):
        return self.timelines[i - 1]

    def SetCurrentTimeline(self, tl):
        self.current = tl
        return True

    def GetCurrentTimeline(self):
        return self.current

    def GetSetting(self, key):
        return self.fps if key == "timelineFrameRate" else None


class Resolve:
    AUTO_ALIGN_CLIPS_USING_WAVEFORM = 1.0
    EXPORT_OTIO = 15.0
    EXPORT_NONE = 0.0


def run(source, project, via_file=None):
    """Execute a generated script like the MCP does; returns `result`."""
    namespace = {"resolve": Resolve(), "project": project}
    if via_file:
        with open(via_file, "w", encoding="ascii") as fh:
            fh.write(source)
        # The exact one-liner shape the agent sends through run_script_unsafe.
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", ResourceWarning)
            exec(f"exec(open({os.fspath(via_file)!r}, encoding='utf-8').read())", namespace)
    else:
        exec(compile(source, "<generated>", "exec"), namespace)
    return namespace["result"]
