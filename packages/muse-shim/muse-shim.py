#!/usr/bin/env python3
"""Loopback bridge from Muse Code to CLIProxyAPI.

Muse Code only speaks to its Meta provider: it posts to
``{base_url}/v1/responses`` (the OpenAI Responses API CLIProxyAPI serves),
but first fetches its model catalog from ``{origin}/muse-code/models`` and
refuses to start when that fetch fails. CLIProxyAPI has no such path, so
this shim serves it from the proxy's own ``/v1/models`` and forwards
everything else, adding the Cloudflare Access service-token headers the
public proxy endpoint requires. Muse itself only ever talks to loopback.

Configuration comes from the environment, set by the Nix wrapper:
``MUSE_SHIM_UPSTREAM``, ``MUSE_SHIM_PORT``, ``MUSE_SHIM_CF_ID_FILE``, and
``MUSE_SHIM_CF_SECRET_FILE``. The secret files are re-read per request so a
rotated token reaches the shim without a restart.
"""

import http.client
import http.server
import json
import os
import urllib.parse

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
}


def cf_headers() -> dict[str, str]:
    """Cloudflare Access headers from the agenix files, when configured."""
    headers: dict[str, str] = {}
    for env, header in (
        ("MUSE_SHIM_CF_ID_FILE", "CF-Access-Client-Id"),
        ("MUSE_SHIM_CF_SECRET_FILE", "CF-Access-Client-Secret"),
    ):
        path = os.environ.get(env)
        if not path:
            continue
        try:
            value = open(path).read().strip()
        except OSError:
            value = ""
        if value:
            headers[header] = value
    return headers


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    upstream = urllib.parse.urlsplit("https://llm.clusters.work")

    def log_message(self, *_args: object) -> None:
        pass

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _forward(self, upstream_path: str) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP
        }
        headers.update(cf_headers())
        upstream = self.upstream
        connection_class = (
            http.client.HTTPSConnection if upstream.scheme == "https" else http.client.HTTPConnection
        )
        connection = connection_class(upstream.hostname, upstream.port, timeout=600)
        try:
            connection.request(self.command, upstream_path, body=body, headers=headers)
            response = connection.getresponse()
            self.send_response(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() not in HOP_BY_HOP | {"content-length"}:
                    self.send_header(key, value)
            # The response is dechunked by http.client and its length is not
            # known up front, so this connection cannot be reused.
            self.send_header("Connection", "close")
            self.end_headers()
            while chunk := response.read(65536):
                self.wfile.write(chunk)
                self.wfile.flush()
        except (OSError, http.client.HTTPException) as error:
            try:
                self._send_json(502, {"error": f"muse-shim: upstream failed: {error}"})
            except OSError:
                pass
        finally:
            connection.close()
            self.close_connection = True

    def _handle(self) -> None:
        path = urllib.parse.urlsplit(self.path).path
        if path == "/healthz":
            self._send_json(200, {"status": "ok"})
        elif path == "/muse-code/models":
            # CLIProxyAPI's model list is already the shape Muse parses.
            self._forward("/v1/models")
        elif path == "/muse-code/config":
            # Feature flags for the Meta service. The 404 is not fatal:
            # Muse continues with its built-in defaults.
            self._send_json(404, {"error": "no feature config on this endpoint"})
        else:
            self._forward(self.path)

    do_GET = _handle
    do_POST = _handle
    do_PUT = _handle
    do_PATCH = _handle
    do_DELETE = _handle


def main() -> None:
    upstream = os.environ.get("MUSE_SHIM_UPSTREAM", "https://llm.clusters.work")
    Handler.upstream = urllib.parse.urlsplit(upstream)
    port = int(os.environ.get("MUSE_SHIM_PORT", "27182"))
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
