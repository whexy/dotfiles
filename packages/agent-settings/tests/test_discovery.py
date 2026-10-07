import json
import threading
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import ClassVar, override

import pytest
from support import SECRET

from agent_settings.catalog import Entry
from agent_settings.discovery import served_models
from agent_settings.errors import SettingsError


class _Handler(BaseHTTPRequestHandler):
    seen: ClassVar[list[dict[str, str]]] = []

    def do_GET(self) -> None:
        self.seen.append(dict(self.headers))
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "http://elsewhere.invalid/v1/models")
            self.end_headers()
            return
        body = json.dumps({"data": [{"id": "b"}, {"id": "a/x"}, {"id": "b"}, {}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    @override
    def log_message(self, format: str, *args: object) -> None:
        pass


@pytest.fixture
def server() -> Iterator[str]:
    httpd = HTTPServer(("127.0.0.1", 0), _Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    _Handler.seen.clear()
    yield f"http://127.0.0.1:{httpd.server_address[1]}"
    httpd.shutdown()


def served(secret: Path, url: str) -> list[str]:
    template: Entry = {
        "label": "proxy",
        "secrets": {"API_KEY": str(secret), "EDGE": str(secret)},
        "secretHeaders": {"X-Edge": "EDGE"},
    }
    return served_models(template, {"url": url, "keyEnv": "API_KEY", "modelEnv": ["MODEL"]})


def test_served_models_sends_credentials(secret: Path, server: str) -> None:
    assert served(secret, f"{server}/v1/models") == ["a/x", "b"]
    headers = _Handler.seen[0]
    assert headers["Authorization"] == f"Bearer {SECRET}"
    assert headers["X-Edge"] == SECRET
    assert not headers["User-Agent"].startswith("Python-urllib")


def test_served_models_refuses_redirects(secret: Path, server: str) -> None:
    with pytest.raises(SettingsError, match="model discovery failed"):
        served(secret, f"{server}/redirect")
    assert len(_Handler.seen) == 1
