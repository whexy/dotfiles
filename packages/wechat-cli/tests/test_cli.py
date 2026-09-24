import email.parser
import email.policy
import json
import os
import sys
import threading
from collections.abc import Callable, Iterator
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, ClassVar, override
from unittest.mock import patch

import pytest

from wechat_cli import cli
from wechat_cli.relay import encode_multipart

type Route = Callable[["Handler"], tuple[int, Any]]


class Handler(BaseHTTPRequestHandler):
    routes: ClassVar[dict[str, Route]] = {}
    requests: ClassVar[list[tuple[str, str, str, bytes]]] = []

    def _serve(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        path = self.path.split("?")[0]
        Handler.requests.append(
            (self.command, self.path, self.headers.get("Content-Type", ""), body)
        )
        route = Handler.routes.get(f"{self.command} {path}")
        code, payload = route(self) if route else (404, {"ok": False, "error": "no route"})
        raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        self._serve()

    def do_POST(self) -> None:
        self._serve()

    def do_DELETE(self) -> None:
        self._serve()

    @override
    def log_message(self, format: str, *args: Any) -> None:
        pass


@pytest.fixture
def relay() -> Iterator[dict[str, Route]]:
    Handler.routes, Handler.requests = {}, []
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}"
    with patch.dict(os.environ, {"WECHAT_RELAY_URL": url}):
        yield Handler.routes
    server.shutdown()


def run(*argv: str) -> int:
    with patch.object(sys, "argv", ["wechat", *argv]):
        try:
            cli.main()
        except SystemExit as exit:
            return int(exit.code or 0)
    return 0


def parse_form(content_type: str, body: bytes) -> EmailMessage:
    raw = f"Content-Type: {content_type}\r\n\r\n".encode() + body
    return email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(raw)  # type: ignore[return-value]


def test_multipart_encoding(tmp_path: Path) -> None:
    shot = tmp_path / 'shot "one" 截图.png'
    shot.write_bytes(b"\x89PNG\r\n--not-a-boundary")
    body, content_type = encode_multipart({"text": "hi 你好", "as": "file"}, [shot])
    parts = list(parse_form(content_type, body).iter_parts())
    assert [p.get_param("name", header="content-disposition") for p in parts] == [
        "text",
        "as",
        "file",
    ]
    assert parts[0].get_payload(decode=True) == "hi 你好".encode()
    assert parts[2].get_filename() == 'shot "one" 截图.png'
    assert parts[2].get_payload(decode=True) == b"\x89PNG\r\n--not-a-boundary"


def test_send_queued(relay: dict[str, Route], capsys: pytest.CaptureFixture[str]) -> None:
    relay["POST /send"] = lambda _: (202, {"ok": True, "queued": 1, "reason": "window closed"})
    assert run("send", "build", "passed") == 0
    assert "queued: window closed" in capsys.readouterr().err
    _, _, content_type, body = Handler.requests[0]
    fields = {
        p.get_param("name", header="content-disposition"): p.get_payload(decode=True)
        for p in parse_form(content_type, body).iter_parts()
    }
    assert fields == {"text": b"build passed"}


@pytest.mark.usefixtures("relay")
def test_send_missing_file(tmp_path: Path) -> None:
    assert run("send", "x", "-f", str(tmp_path / "nope")) == 1
    assert Handler.requests == []


def test_ask_downloads_reply(
    relay: dict[str, Route], tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    polls = iter(
        [
            {"id": "a1", "state": "waiting"},
            {
                "id": "a1",
                "state": "answered",
                "reply": {
                    "text": "looks good",
                    "quote": "deploy?",
                    "attachments": [
                        {"kind": "image", "name": "image.jpg", "url": "/api/asks/a1/files/0"},
                        {"kind": "file", "name": "x.pdf", "error": "download failed"},
                    ],
                },
            },
        ]
    )
    relay["POST /send"] = lambda _: (200, {"ok": True, "ask_id": "a1", "message_ids": ["1"]})
    relay["GET /api/asks/a1"] = lambda _: (200, next(polls))
    relay["GET /api/asks/a1/files/0"] = lambda _: (200, b"jpeg")

    code = run("ask", "Deploy?", "--timeout", "60", "--download", str(tmp_path), "--json")
    assert code == 0
    reply = json.loads(capsys.readouterr().out)
    assert reply["text"] == "looks good"
    image, pdf = reply["attachments"]
    assert Path(image["path"]).read_bytes() == b"jpeg"
    assert "url" not in image
    assert pdf["error"] == "download failed"
    _, _, content_type, body = Handler.requests[0]
    fields = {
        p.get_param("name", header="content-disposition"): p.get_payload(decode=True)
        for p in parse_form(content_type, body).iter_parts()
    }
    assert fields == {"text": b"Deploy?", "require_reply": b"true", "timeout": b"60.0"}


def test_ask_expired(relay: dict[str, Route], capsys: pytest.CaptureFixture[str]) -> None:
    relay["POST /send"] = lambda _: (202, {"ok": True, "ask_id": "a2", "reason": "held"})
    relay["GET /api/asks/a2"] = lambda _: (200, {"id": "a2", "state": "expired"})
    assert run("ask", "q") == 3
    assert "no reply" in capsys.readouterr().err


def test_ask_cancelled_elsewhere(relay: dict[str, Route]) -> None:
    relay["POST /send"] = lambda _: (200, {"ok": True, "ask_id": "a3"})
    relay["GET /api/asks/a3"] = lambda _: (200, {"id": "a3", "state": "cancelled"})
    assert run("ask", "q") == 1


def test_status(relay: dict[str, Route], capsys: pytest.CaptureFixture[str]) -> None:
    relay["GET /api/status"] = lambda _: (200, {"state": "expired"})
    assert run("status") == 1
    assert "scan the QR code" in capsys.readouterr().out
    relay["GET /api/status"] = lambda _: (
        200,
        {"state": "online", "window_open": True, "window_remaining": "3h00m", "queued": 0},
    )
    assert run("status") == 0
    assert "open for 3h00m" in capsys.readouterr().out


def test_unreachable(capsys: pytest.CaptureFixture[str]) -> None:
    with patch.dict(os.environ, {"WECHAT_RELAY_URL": "http://127.0.0.1:9"}):
        assert run("status") == 1
    assert "cannot reach the relay" in capsys.readouterr().err
