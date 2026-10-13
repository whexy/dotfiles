import http.client
import http.server
import importlib.util
import json
import os
import threading
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("shim", Path(__file__).parent.parent / "muse-shim.py")
assert SPEC and SPEC.loader
shim = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shim)

SEEN: list[tuple[str, str, dict[str, str]]] = []


class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args: object) -> None:
        pass

    def _handle(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        SEEN.append((self.command, self.path, dict(self.headers)))
        if self.path == "/v1/models":
            payload = {"object": "list", "data": [{"id": "model-1", "object": "model"}]}
        else:
            payload = {"echo": body.decode()}
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = _handle
    do_POST = _handle


def serve(handler: type[http.server.BaseHTTPRequestHandler]) -> http.server.HTTPServer:
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class ShimTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.upstream = serve(Upstream)

    def setUp(self) -> None:
        SEEN.clear()
        self.cf_id = Path(__file__).parent / "cf-id.tmp"
        self.cf_secret = Path(__file__).parent / "cf-secret.tmp"
        self.cf_id.write_text("id-123\n")
        self.cf_secret.write_text("secret-456\n")
        os.environ["MUSE_SHIM_CF_ID_FILE"] = str(self.cf_id)
        os.environ["MUSE_SHIM_CF_SECRET_FILE"] = str(self.cf_secret)
        shim.Handler.upstream = shim.urllib.parse.urlsplit(
            f"http://127.0.0.1:{self.upstream.server_address[1]}"
        )
        self.shim_server = serve(shim.Handler)
        self.port = self.shim_server.server_address[1]

    def tearDown(self) -> None:
        self.shim_server.shutdown()
        self.cf_id.unlink(missing_ok=True)
        self.cf_secret.unlink(missing_ok=True)

    def request(self, method: str, path: str, body: str | None = None) -> tuple[int, object]:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        connection.request(method, path, body=body, headers={"Authorization": "Bearer key-1"})
        response = connection.getresponse()
        payload: object = json.loads(response.read())
        connection.close()
        return response.status, payload

    def test_catalog_comes_from_v1_models_with_cf_headers(self) -> None:
        status, payload = self.request("GET", "/muse-code/models")
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"object": "list", "data": [{"id": "model-1", "object": "model"}]})
        method, path, headers = SEEN[-1]
        self.assertEqual((method, path), ("GET", "/v1/models"))
        self.assertEqual(headers.get("CF-Access-Client-Id"), "id-123")
        self.assertEqual(headers.get("CF-Access-Client-Secret"), "secret-456")
        self.assertEqual(headers.get("Authorization"), "Bearer key-1")

    def test_responses_are_forwarded(self) -> None:
        status, payload = self.request("POST", "/v1/responses", '{"model":"model-1"}')
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"echo": '{"model":"model-1"}'})
        self.assertEqual(SEEN[-1][1], "/v1/responses")

    def test_feature_config_is_a_plain_404(self) -> None:
        status, _ = self.request("GET", "/muse-code/config?channel=public")
        self.assertEqual(status, 404)
        self.assertEqual(SEEN, [])


if __name__ == "__main__":
    unittest.main()
