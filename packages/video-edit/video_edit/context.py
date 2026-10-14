"""An edit root's spec, sources, transcript, silences and EDL, loaded once."""

from . import silence, timeline, transcript


class Edit:
    def __init__(self, root):
        self.root = root
        self.spec = root.spec()
        self.sources = root.sources()
        self.main = self.sources["main"]
        self.camera = self.sources.get("camera")
        self.fps = self.spec["timeline"]["fps"]
        self.cuts = timeline.cut_settings(self.spec)
        self.transcript_path = root.transcript_path(self.main["path"])
        self._words = None
        self._silences = None

    @property
    def words(self):
        if self._words is None:
            _, self._words = transcript.load(self.transcript_path)
        return self._words

    @property
    def silences(self):
        if self._silences is None:
            data = silence.load(self.root, self.main, self.spec)
            self._silences = silence.Silences(data["silences"])
        return self._silences

    def validate(self):
        errors = timeline.check_fps(self.spec, self.sources)
        if errors:
            return {"errors": errors, "warnings": [], "ranges": [], "overlays": []}
        return timeline.validate(
            self.root.edl(),
            self.words,
            self.silences,
            self.fps,
            self.main["duration"],
            self.cuts,
        )
