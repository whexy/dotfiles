"""HTTP client for wechat-relay, the tailnet service holding the one WeChat bot login.

Only one bot can be bound to the user's WeChat, so every machine sends through
the relay instead of logging in itself. The relay is tailnet-only and has no
authentication.
"""

import contextlib
import json
import os
import secrets
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_URL = "https://wechat.at-basking.ts.net"
API_TIMEOUT = 30.0
# Attachments are uploaded to the CDN before /send answers.
SEND_TIMEOUT = 300.0

type Json = dict[str, Any]


class RelayError(Exception):
    def __init__(self, message: str, status: int | None = None) -> None:
        super().__init__(message)
        self.status: int | None = status

    @property
    def transient(self) -> bool:
        return self.status is None or self.status >= 500


def base_url() -> str:
    return (os.environ.get("WECHAT_RELAY_URL") or DEFAULT_URL).rstrip("/")


def encode_multipart(fields: dict[str, str], files: list[Path]) -> tuple[bytes, str]:
    """Encode form fields and `file` parts as multipart/form-data."""
    boundary = f"wechat-cli-{secrets.token_hex(12)}"
    out: list[bytes] = []
    for name, value in fields.items():
        out += [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
            value.encode(),
            b"\r\n",
        ]
    for path in files:
        # RFC 7578: raw UTF-8 with quotes escaped, not percent-encoding.
        filename = "".join(c for c in path.name if c not in "\r\n")
        filename = filename.replace("\\", "\\\\").replace('"', '\\"')
        out += [
            f"--{boundary}\r\n".encode(),
            (
                f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
                "Content-Type: application/octet-stream\r\n\r\n"
            ).encode(),
            path.read_bytes(),
            b"\r\n",
        ]
    out.append(f"--{boundary}--\r\n".encode())
    return b"".join(out), f"multipart/form-data; boundary={boundary}"


class Relay:
    def __init__(self, url: str | None = None) -> None:
        self.url: str = (url or base_url()).rstrip("/")

    def _open(
        self,
        method: str,
        path: str,
        timeout: float,
        body: bytes | None = None,
        content_type: str | None = None,
    ) -> tuple[int, bytes]:
        request = urllib.request.Request(self.url + path, data=body, method=method)
        if content_type:
            request.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            with contextlib.suppress(ValueError, AttributeError):
                detail = json.loads(detail).get("error") or detail
            raise RelayError(f"relay: HTTP {error.code}: {detail}".strip(), error.code) from error
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            reason = getattr(error, "reason", error)
            raise RelayError(f"cannot reach the relay at {self.url}: {reason}") from error

    def _json(self, method: str, path: str, timeout: float = API_TIMEOUT, **kw: Any) -> Json:
        _, raw = self._open(method, path, timeout, **kw)
        return json.loads(raw)

    def status(self) -> Json:
        return self._json("GET", "/api/status")

    def send(
        self,
        text: str,
        files: list[Path],
        kind: str | None = None,
        require_reply: bool = False,
        timeout: float | None = None,
    ) -> tuple[int, Json]:
        """Post a message; the status is 200 when delivered and 202 when queued."""
        fields = {"text": text}
        if kind:
            fields["as"] = kind
        if require_reply:
            fields["require_reply"] = "true"
        if timeout is not None:
            fields["timeout"] = str(timeout)
        body, content_type = encode_multipart(fields, files)
        code, raw = self._open("POST", "/send", SEND_TIMEOUT, body, content_type)
        return code, json.loads(raw)

    def wait_ask(self, ask_id: str, wait: int) -> Json:
        path = f"/api/asks/{urllib.parse.quote(ask_id)}?wait={wait}"
        return self._json("GET", path, timeout=wait + API_TIMEOUT)

    def cancel(self, ask_id: str) -> None:
        self._open("DELETE", f"/api/asks/{urllib.parse.quote(ask_id)}", timeout=5)

    def fetch(self, path: str) -> bytes:
        return self._open("GET", path, SEND_TIMEOUT)[1]
