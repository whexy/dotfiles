import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from websockets.sync.client import connect


def read(path, default):
    return json.loads(path.read_text()) if path.exists() else default


def write(path, value):
    temporary = path.with_suffix(".new")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def tailscale(args):
    root = Path(os.environ["T3_TEST_ROOT"])
    if not (root / "online").exists():
        return 1
    config = root / "routes.json"
    if args == ["status", "--json"]:
        print(json.dumps({"BackendState": "Running", "Self": {"DNSName": "localhost." if (root / "actual-dns").exists() else "fixture.ts.net."}}))
    elif args == ["serve", "status", "--json"]:
        print(config.read_text())
    else:
        assert args == ["serve", "--bg", "--https=35338", "http://127.0.0.1:3773"], args
        if (root / "fail-serve").exists():
            return 1
        routes = read(config, {})
        routes.setdefault("Web", {}).setdefault("fixture.ts.net:35338", {}).setdefault("Handlers", {})["/"] = {"Proxy": "http://127.0.0.1:3773"}
        write(config, routes)
        with (root / "writes").open("a") as output:
            output.write("setup\n")
    return 0


def serve(args):
    assert os.environ["T3_TEST_SESSION"] == "loaded"
    assert args == ["serve", "--host", "127.0.0.1", "--port", "3773", "--no-browser", "--tailscale-serve", "--tailscale-serve-port", "35338"], args
    root = Path(os.environ["T3_TEST_ROOT"])

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            assert self.path == "/.well-known/t3/environment"
            routes = read(root / "routes.json", {})
            endpoints = []
            if (root / "online").exists() and routes.get("Web", {}).get("fixture.ts.net:35338", {}).get("Handlers", {}).get("/", {}).get("Proxy") == "http://127.0.0.1:3773":
                endpoints.append("https://fixture.ts.net:35338/")
            body = json.dumps({"pid": os.getpid(), "endpoints": endpoints}).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    (root / "port").write_text(str(httpd.server_port))
    httpd.serve_forever()


def test(server_script, route_script):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        unrelated = {"Web": {"fixture.ts.net:443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:9999"}}}, "fixture.ts.net:35338": {"Handlers": {"/other": {"Proxy": "http://127.0.0.1:9998"}}}}}
        write(root / "routes.json", unrelated)
        env = dict(os.environ, T3_TEST_ROOT=directory)
        server = subprocess.Popen([server_script], env=env, start_new_session=True)
        route = subprocess.Popen([route_script], env=env, start_new_session=True)
        proxy = None
        try:
            def wait_for(fn, seconds=35):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    assert server.poll() is None and route.poll() is None
                    if fn():
                        return
                    time.sleep(0.05)
                raise AssertionError("fixture timed out")

            wait_for(lambda: (root / "port").exists(), 3)
            port = int((root / "port").read_text())

            # A disposable reverse proxy exercises the public tunnel's loopback backend.
            class Proxy(BaseHTTPRequestHandler):
                def do_GET(self):
                    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
                    connection.request("GET", self.path)
                    response = connection.getresponse()
                    body = response.read()
                    self.send_response(response.status)
                    self.end_headers()
                    self.wfile.write(body)
                    connection.close()

                def log_message(self, *args):
                    pass

            proxy = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
            threading.Thread(target=proxy.serve_forever, daemon=True).start()

            def discovery(target_port):
                with urllib.request.urlopen(f"http://127.0.0.1:{target_port}/.well-known/t3/environment", timeout=2) as response:
                    return json.load(response)

            initial = discovery(port)
            assert initial["endpoints"] == []
            assert discovery(proxy.server_port) == initial
            (root / "fail-serve").touch()
            (root / "online").touch()
            time.sleep(11)
            assert discovery(port) == initial
            (root / "fail-serve").unlink()
            wait_for(lambda: discovery(port)["endpoints"] != [])
            assert discovery(proxy.server_port)["pid"] == initial["pid"]
            routes = read(root / "routes.json", {})
            assert routes["Web"]["fixture.ts.net:443"] == unrelated["Web"]["fixture.ts.net:443"]
            assert routes["Web"]["fixture.ts.net:35338"]["Handlers"]["/other"] == unrelated["Web"]["fixture.ts.net:35338"]["Handlers"]["/other"]
            writes = (root / "writes").read_text()
            time.sleep(11)
            assert (root / "writes").read_text() == writes
            # Lost Serve config is repaired without replacing the server.
            write(root / "routes.json", unrelated)
            wait_for(lambda: len((root / "writes").read_text()) > len(writes))
            assert discovery(port)["pid"] == initial["pid"]
            print("offline loopback/public backend, route retries/recovery, discovery flag, Linux/Darwin parity, unrelated routes: passed")
        finally:
            if proxy:
                proxy.shutdown()
            for process in (server, route):
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=3)


def actual(binary, fixture_bin):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        def unused_port():
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                return sock.getsockname()[1]
        port = unused_port()
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(root / "key.pem"), "-out", str(root / "cert.pem"), "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"], check=True, capture_output=True)

        class Proxy(BaseHTTPRequestHandler):
            def do_GET(self):
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                connection.request("GET", self.path)
                response = connection.getresponse()
                body = response.read()
                self.send_response(response.status)
                self.end_headers()
                self.wfile.write(body)
                connection.close()
            def log_message(self, *args):
                pass

        proxy = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(root / "cert.pem", root / "key.pem")
        proxy.socket = context.wrap_socket(proxy.socket, server_side=True)
        # Start the TLS route only after T3 has already started offline.
        env = dict(os.environ, HOME=directory, T3_TEST_ROOT=directory, PATH=f"{fixture_bin}:{os.environ['PATH']}", NODE_EXTRA_CA_CERTS=str(root / "cert.pem"), T3CODE_TELEMETRY_ENABLED="false", T3CODE_OTEL_SDK_DISABLED="true")
        log = (root / "server.log").open("w+")
        process = subprocess.Popen([binary, "serve", "--base-dir", str(root / "data"), "--host", "127.0.0.1", "--port", str(port), "--tailscale-serve", "--tailscale-serve-port", str(proxy.server_port), "--no-browser"], env=env, cwd=directory, stdout=log, stderr=log, start_new_session=True)
        try:
            def discovery():
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/.well-known/t3/environment", timeout=5) as response:
                    return json.load(response)
            deadline = time.monotonic() + 25
            while True:
                try:
                    initial = discovery()
                    break
                except (OSError, ValueError):
                    if time.monotonic() > deadline or process.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.1)
            token = subprocess.run([binary, "auth", "session", "issue", "--base-dir", str(root / "data"), "--token-only"], env=env, cwd=directory, text=True, capture_output=True, check=True, timeout=10).stdout.strip()
            def config():
                with connect(f"ws://127.0.0.1:{port}/ws?orchestrationProtocol=2", additional_headers={"Authorization": f"Bearer {token}"}, open_timeout=5) as ws:
                    ws.send(json.dumps({"_tag": "Request", "id": "0", "tag": "server.getConfig", "payload": {}, "headers": []}))
                    result = ws.recv(timeout=8)
                    return json.loads(result)
            initial = config()
            expected = f"https://localhost:{proxy.server_port}/"
            assert expected not in json.dumps(initial), initial
            # Discovery resolves on every request, so a repaired route needs no restart.
            (root / "actual-dns").touch()
            (root / "online").touch()
            threading.Thread(target=proxy.serve_forever, daemon=True).start()
            deadline = time.monotonic() + 15
            while True:
                found = config()
                if expected in json.dumps(found):
                    break
                if time.monotonic() > deadline:
                    log.seek(0)
                    raise AssertionError(f"discovery did not advertise route: {found}\n{log.read()}")
                time.sleep(0.2)
            assert process.poll() is None
            print("pinned T3 executable: offline startup and dynamic tailnet discovery passed")
        finally:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            proxy.server_close()
            log.close()

if __name__ == "__main__":
    if sys.argv[1] == "tailscale":
        sys.exit(tailscale(sys.argv[2:]))
    elif sys.argv[1] == "actual":
        actual(*sys.argv[2:])
    elif sys.argv[1] == "server":
        serve(sys.argv[2:])
    else:
        test(*sys.argv[2:])
