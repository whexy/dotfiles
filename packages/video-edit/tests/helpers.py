"""Synthetic edit roots: a 8 s talk with known words and silences, no media."""

import json
import shutil
import tempfile
from pathlib import Path

from video_edit import silence
from video_edit.common import Root, write_json
from video_edit.project import default_spec

FPS = 60
# (word, start, end); silences sit between the groups.
WORDS = [
    ("大", 1.00, 1.20), ("家", 1.20, 1.40), ("好", 1.40, 1.70),
    ("嗯", 2.50, 2.70),
    ("今", 3.30, 3.50), ("天", 3.50, 3.70), ("讲", 3.70, 3.90),
    ("k", 3.90, 4.00), ("ubernetes", 4.00, 4.50),
    ("然", 5.40, 5.60), ("后", 5.60, 5.80), ("结", 5.80, 6.00), ("束", 6.00, 6.30),
]
SILENCES = [[0.0, 1.0], [1.7, 2.5], [2.7, 3.3], [4.5, 5.4], [6.3, 8.0]]
DURATION = 8.0
# Edges 5 frames (83 ms) before onset and 15 frames (250 ms) after offset.
RANGES = [
    {"start": 55 / FPS, "end": 117 / FPS, "section": "S01"},
    {"start": 193 / FPS, "end": 285 / FPS, "section": "S01"},
    {"start": 319 / FPS, "end": 393 / FPS, "section": "S02"},
]


def words():
    return [
        {"word": w, "start": s, "end": e, "filler": w == "嗯", "stumble": False, "index": i}
        for i, (w, s, e) in enumerate(WORDS)
    ]


def transcript_json():
    ws = [
        {"word": w, "start": s, "end": e, "gap_after": None, "filler": False, "stumble": False}
        for w, s, e in WORDS
    ]
    return {
        "source": "main.mkv",
        "duration": DURATION,
        "model": "whisper-1",
        "segments": [{"index": 0, "start": 1.0, "end": 6.3, "words": ws}],
        "silences": [],
    }


class EditRoot:
    """A temporary edit root; `close()` removes it."""

    def __init__(self, edl=None, camera=True):
        self.tmp = Path(tempfile.mkdtemp(prefix="video-edit-test-"))
        footage = self.tmp / "Records"
        footage.mkdir()
        main = footage / "main.mkv"
        main.write_bytes(b"stub")
        self.root = Root(footage / "edit" / "Demo")
        self.root._windows = r"D:\Records\edit\Demo"
        for d in ("transcripts", "slots", "resolve", "verify", "subtitles", "style"):
            (self.root / d).mkdir(parents=True)
        source = {
            "path": str(main),
            "windows_path": r"D:\Records\main.mkv",
            "file_name": "main.mkv",
            "fps": FPS,
            "fps_rational": "60/1",
            "frames": int(DURATION * FPS),
            "duration": DURATION,
            "width": 3840,
            "height": 2160,
            "has_audio": True,
            "start_timecode": "00:00:00:00",
        }
        sources = {"version": 1, "main": source}
        if camera:
            sources["camera"] = {
                **source,
                "path": str(footage / "cam.mkv"),
                "windows_path": r"D:\Records\cam.mkv",
                "file_name": "cam.mkv",
                "offset_frames": 15,
                "offset_changes": [],
            }
        write_json(self.root.sources_path, sources)
        self.spec = default_spec("Demo", source)
        write_json(self.root.spec_path, self.spec)
        write_json(self.root / "transcripts" / "main.json", transcript_json())
        stat = main.stat()
        write_json(
            self.root / "transcripts" / "main.silences.json",
            {
                "source": str(main),
                "size": stat.st_size,
                "mtime_ns": stat.st_mtime_ns,
                "settings": silence.settings(self.spec),
                "noise_floor_db": -44.5,
                "threshold_db": -35.5,
                "threshold_from": "test",
                "min_duration": 0.05,
                "count": len(SILENCES),
                "silences": SILENCES,
            },
        )
        self.write_edl(edl or default_edl())

    def write_edl(self, edl):
        self.root.edl_path.write_text(json.dumps(edl, ensure_ascii=False), encoding="utf-8")

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


def default_edl():
    return {
        "version": 1,
        "name": "Demo",
        "ranges": [dict(r) for r in RANGES],
        "overlays": [
            {"slot": "G1", "anchor": 4.0, "lead": 0.45, "duration": 2.0, "reason": "k8s"}
        ],
    }
