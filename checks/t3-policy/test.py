import fcntl
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VALID_A = b'{"valid": true, "rev": "a"}\n'
VALID_B = b'{"valid": true, "rev": "b"}\n'
INVALID = b'{"valid": false}\n'


def sha(body):
    return hashlib.sha256(body).hexdigest()


class Fixture:
    def __init__(self):
        self.body = VALID_A
        self.code = 200
        self.requests = []
        self.alerts = []
        # Called while answering a GET, to change the world mid-request.
        self.on_get = None
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                assert self.path == "/dotfiles.json", self.path
                fixture.requests.append(self.headers.get("If-None-Match"))
                if fixture.on_get:
                    fixture.on_get()
                etag = f'"{sha(fixture.body)}"'
                if fixture.code != 200:
                    self.send_response(fixture.code)
                    self.end_headers()
                    return
                if self.headers.get("If-None-Match") == etag:
                    self.send_response(304)
                    self.send_header("ETag", etag)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("ETag", etag)
                self.send_header("Content-Length", str(len(fixture.body)))
                self.end_headers()
                self.wfile.write(fixture.body)

            def do_POST(self):
                assert self.path == "/alert", self.path
                fixture.alerts.append(
                    json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                )
                self.send_response(200)
                self.end_headers()

            def log_message(self, *args):
                pass

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.origin = f"http://127.0.0.1:{self.httpd.server_port}"


def test(command):
    fixture = Fixture()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        state = root / "state" / "t3code-policy"
        env = dict(
            os.environ,
            HOME=directory,
            XDG_STATE_HOME=str(root / "state"),
            T3_TEST_ROOT=directory,
            T3CODE_POLICY_URL=f"{fixture.origin}/dotfiles.json",
            T3CODE_POLICY_ALERT_URL=f"{fixture.origin}/alert",
        )

        def run(*args, url=None, **extra):
            run_env = dict(env, **extra)
            if url:
                run_env["T3CODE_POLICY_URL"] = url
            result = subprocess.run(
                [command, *args], env=run_env, text=True, capture_output=True, timeout=60
            )
            assert result.returncode == 0, result
            return result

        def status():
            return json.loads((state / "status.json").read_text())

        def restarts():
            path = root / "restarts"
            return len(path.read_text().splitlines()) if path.exists() else 0

        def checks():
            path = root / "checks"
            return len(path.read_text().splitlines()) if path.exists() else 0

        def states():
            return [alert["title"].rsplit(": ", 1)[1] for alert in fixture.alerts]

        def update(expected, restarted, url=None):
            run("update", url=url)
            current = status()
            assert current["update"]["result"] == expected, current
            assert restarts() == restarted, (expected, restarts())
            return current

        # The wrapper's start applies A.
        assert run("resolve").stdout.strip() == str(state / "policy.json")
        assert status()["state"] == "current"
        assert status()["applied_sha256"] == sha(VALID_A)

        # A stopped server is neither fetched for nor started.
        update("server-stopped", 0)
        assert fixture.requests == [None]
        (root / "running").touch()

        update("unchanged", 0)
        assert fixture.requests[-1] == f'"{sha(VALID_A)}"'
        assert fixture.alerts == []

        # A server stopped while the policy downloads stays stopped.
        fixture.body = VALID_B
        fixture.on_get = lambda: (root / "running").unlink()
        update("server-stopped", 0)
        fixture.on_get = None
        (root / "running").touch()

        # A changed valid policy restarts the server once.
        current = update("restarted", 1)
        assert current["update"]["restarted_for"] == sha(VALID_B)

        # The start fell back to A, so the same sha waits out the hour.
        update("backoff", 1)
        current["update"]["restarted_at"] = "2000-01-01T00:00:00Z"
        (state / "status.json").write_text(json.dumps(current))
        update("restarted", 2)

        # The start applies B; the update record survives it.
        run("resolve")
        assert status()["applied_sha256"] == sha(VALID_B)
        assert status()["update"]["restarted_for"] == sha(VALID_B)
        update("unchanged", 2)

        # An invalid policy alerts once, restarts nothing, and is checked once.
        fixture.body = INVALID
        checked = checks()
        current = update("invalid", 2)
        assert current["state"] == "stale-invalid", current
        assert "policy is invalid" in current["error"], current
        current = update("invalid", 2)
        assert "policy is invalid" in current["update"]["error"], current
        assert checks() == checked + 1
        assert states() == ["stale-invalid"]

        # The applied policy served again is current again.
        fixture.body = VALID_B
        current = update("unchanged", 2)
        assert current["state"] == "current" and current["error"] is None, current
        assert [alert["severity"] for alert in fixture.alerts] == ["warn", "ok"]

        # A deleted policy alerts once and restarts nothing, until it is back.
        fixture.code = 404
        current = update("missing", 2)
        assert current["state"] == "stale-missing", current
        assert current["error"] == "missing: HTTP 404", current
        fixture.code = 410
        update("missing", 2)
        assert states() == ["stale-invalid", "current", "stale-missing"]
        fixture.code = 200
        assert update("unchanged", 2)["state"] == "current"
        assert states()[-1] == "current" and len(fixture.alerts) == 4

        # A start finds it deleted too, and keeps the last good copy.
        fixture.code = 404
        assert run("resolve").stdout.strip() == str(state / "policy.json")
        assert status()["state"] == "stale-missing" and status()["applied_sha256"] == sha(VALID_B)
        assert states()[-1] == "stale-missing" and len(fixture.alerts) == 5
        fixture.code = 200
        run("resolve")
        assert status()["state"] == "current" and len(fixture.alerts) == 6

        # Unreachable or failing, nothing restarts and nothing alerts.
        fixture.body = VALID_A
        fixture.code = 503
        assert "HTTP 503" in update("unreachable", 2)["update"]["error"]
        update("unreachable", 2, url="http://127.0.0.1:9/dotfiles.json")
        assert status()["state"] == "current"
        assert len(fixture.alerts) == 6

        # A start holding the lock makes the timer skip its run.
        fixture.code = 200
        requests = len(fixture.requests)
        with (state / ".lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            run("update")
            # A start that cannot take the lock loads the last good copy and
            # writes nothing.
            before = (state / "status.json").read_bytes()
            result = run("resolve", T3CODE_POLICY_LOCK_WAIT="1")
            assert result.stdout.strip() == str(state / "policy.json"), result
            assert "state=locked" in result.stderr, result
            assert (state / "status.json").read_bytes() == before
        assert len(fixture.requests) == requests
        assert restarts() == 2

        log = run("update").stderr
        assert "t3code-policy: update=restarted" in log, log
        assert restarts() == 3
    print(
        "t3code-policy: stopped, stopped mid-fetch, 304, restart, backoff, invalid, missing, unreachable and lock passed"
    )


if __name__ == "__main__":
    test(sys.argv[1])
