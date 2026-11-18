r"""Dictation helper for the wetype-dictate fcitx5 addon.

Records the microphone and streams it to wetype-asr's realtime endpoint
until stdin closes, then waits for the polished transcript. It reports to
the addon on stdout as `<kind>\t<text>` lines, with backslash and newline
in the text escaped as `\\` and `\n`:

- `partial`: the raw transcript so far, which replaces the previous one.
- `status`: a short state for the input panel.
- `final`: the transcript to commit; the helper then exits.
- `error`: the raw text recognised before the failure, possibly empty, to
  commit so that nothing said is lost; the helper then exits.

When the stream fails, recording goes on until stdin closes and the whole
recording is sent to the batch API instead, so nothing said is lost to a
dropped connection.
"""

import base64
import contextlib
import http.client
import io
import json
import os
import queue
import shlex
import subprocess
import sys
import threading
import urllib.parse
import uuid
import wave

from websockets.sync.client import connect

BASE_URL = os.environ.get("WETYPE_DICTATE_URL", "https://wetype-asr.at-basking.ts.net")
RATE = 16000
# The service ends a session past 5 minutes of audio.
MAX_BYTES = 300 * RATE * 2
RECORDER = [
    "pw-record",
    "--raw",
    "--rate",
    str(RATE),
    "--channels",
    "1",
    "--format",
    "s16",
    "--latency",
    "100ms",
    "-",
]

out_lock = threading.Lock()


def emit(kind, text=""):
    escaped = text.replace("\\", "\\\\").replace("\n", "\\n")
    with out_lock:
        sys.stdout.write(f"{kind}\t{escaped}\n")
        sys.stdout.flush()


class Recording:
    """The microphone, read into a queue for the stream and kept whole for
    the batch fallback."""

    def __init__(self):
        override = os.environ.get("WETYPE_DICTATE_RECORDER")
        command = shlex.split(override) if override else RECORDER
        self.proc = subprocess.Popen(command, stdout=subprocess.PIPE, stdin=subprocess.DEVNULL)
        self.chunks = queue.Queue()
        self.pcm = bytearray()
        self.done = threading.Event()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        while chunk := self.proc.stdout.read1(3200):
            room = MAX_BYTES - len(self.pcm)
            chunk = chunk[:room]
            if chunk:
                self.pcm += chunk
                self.chunks.put(chunk)
            if room <= len(chunk):
                emit("status", "5 minute limit reached")
                self.stop()
                break
        self.chunks.put(None)
        self.done.set()

    def stop(self):
        with contextlib.suppress(ProcessLookupError):
            self.proc.terminate()

    def wav(self):
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(bytes(self.pcm))
        return buf.getvalue()


def stream(rec, seen):
    """The polished transcript over the realtime endpoint. The raw text
    recognised so far is kept in seen["raw"] for a failure to report."""
    url = BASE_URL.replace("https://", "wss://", 1).replace("http://", "ws://", 1)
    with connect(f"{url}/v1/realtime?intent=transcription", open_timeout=10, close_timeout=2) as ws:
        ws.send(
            json.dumps(
                {
                    "type": "transcription_session.update",
                    "session": {
                        "input_audio_format": "pcm16",
                        "input_audio_sample_rate": RATE,
                        "include_partials": True,
                    },
                }
            )
        )

        def send():
            with contextlib.suppress(Exception):
                while (chunk := rec.chunks.get()) is not None:
                    ws.send(
                        json.dumps(
                            {
                                "type": "input_audio_buffer.append",
                                "audio": base64.b64encode(chunk).decode(),
                            }
                        )
                    )
                ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
                emit("status", "Polishing…")

        threading.Thread(target=send, daemon=True).start()
        for message in ws:
            event = json.loads(message)
            kind = event.get("type", "")
            if kind.endswith(".partial"):
                seen["raw"] = event["text"]
                emit("partial", seen["raw"])
            elif kind.endswith(".completed"):
                return event["transcript"]
            elif kind == "error":
                err = event.get("error", {})
                raise RuntimeError(f"{err.get('code')}: {err.get('message')}")
    raise RuntimeError("stream closed before the transcript")


def batch(rec):
    body = bytearray()
    boundary = f"dictate-{uuid.uuid4().hex}"
    body += (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="model"\r\n\r\nwhisper-1\r\n'
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="dictation.wav"\r\n'
        "Content-Type: audio/wav\r\n\r\n"
    ).encode()
    body += rec.wav()
    body += f"\r\n--{boundary}--\r\n".encode()
    parts = urllib.parse.urlsplit(BASE_URL)
    cls = http.client.HTTPSConnection if parts.scheme == "https" else http.client.HTTPConnection
    conn = cls(parts.netloc, timeout=120)
    try:
        conn.request(
            "POST",
            "/v1/audio/transcriptions",
            bytes(body),
            {"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        resp = conn.getresponse()
        reply = resp.read().decode("utf-8", "replace")
    finally:
        conn.close()
    if resp.status != 200:
        raise RuntimeError(f"HTTP {resp.status}: {reply[:200]}")
    return json.loads(reply)["text"]


def main():
    rec = Recording()

    def wait_stdin():
        # The raw descriptor, not sys.stdin: a daemon thread blocked in a
        # buffered read aborts interpreter shutdown.
        while os.read(0, 4096):
            pass
        rec.stop()

    threading.Thread(target=wait_stdin, daemon=True).start()
    emit("status", "Listening…")
    seen = {"raw": ""}
    try:
        emit("final", stream(rec, seen))
        return 0
    except Exception as err:
        print(f"wetype-dictate: stream failed: {err}", file=sys.stderr)
        if not rec.done.is_set():
            emit("status", "Connection lost, still recording…")
    rec.done.wait()
    if not rec.pcm:
        emit("status", "No audio recorded")
        emit("error", seen["raw"])
        return 1
    emit("status", "Transcribing…")
    try:
        emit("final", batch(rec))
        return 0
    except Exception as err:
        print(f"wetype-dictate: batch failed: {err}", file=sys.stderr)
        emit("status", "Dictation failed")
        emit("error", seen["raw"])
        return 1


if __name__ == "__main__":
    sys.exit(main())
