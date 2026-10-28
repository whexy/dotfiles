"""MCP stdio proxy that binds iPhone Use to one tailnet phone per session.

A session starts with no phone. The agent lists the phones, asks the user
which one to use, and selects it; every iPhone Use tool then runs against that
phone's WebDriverAgent. iPhone Use only talks to loopback, so the proxy
forwards a loopback port to the phone's Tailscale address. iPhone Use's own
setup tools are hidden: they drive xcodebuild, while `iphone-wda` launches the
runner here.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from pathlib import Path

CONFIG_PATH = (
    Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "iphone-wda/config.json"
)
STATE = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "iphone-use/phones"
HIDDEN = {"pua_setup", "pua_doctor"}
LAUNCH_TIMEOUT = 180

INSTRUCTIONS = (
    "Phones: this server starts each session with no phone selected. Call pua_phones, "
    "ask the user which phone to use (unless they already named one), then call "
    "pua_select_phone before any other tool. The choice holds for this session. If the "
    "selected phone's WebDriverAgent does not answer, call pua_launch_phone once; if that "
    "fails, tell the user what it reported."
)


def tailnet_ipv4(host: str) -> str:
    """The runner binds only the phone's Tailscale IPv4 address."""
    return socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]


def wda_status(host: str, port: int) -> dict | None:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(f"http://{tailnet_ipv4(host)}:{port}/status", timeout=3) as response:
            return json.load(response).get("value") or {}
    except (OSError, ValueError, urllib.error.URLError):
        return None


def pump(source: socket.socket, sink: socket.socket) -> None:
    try:
        while data := source.recv(65536):
            sink.sendall(data)
    except OSError:
        pass
    finally:
        for end in (source, sink):
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


class Forward:
    """A loopback port relaying each connection to the phone's runner."""

    def __init__(self, host: str, port: int) -> None:
        self.target = (host, port)
        self.listener = socket.create_server(("127.0.0.1", 0))
        self.port = self.listener.getsockname()[1]
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self) -> None:
        while True:
            try:
                client, _ = self.listener.accept()
            except OSError:
                return
            threading.Thread(target=self.relay, args=(client,), daemon=True).start()

    def relay(self, client: socket.socket) -> None:
        try:
            upstream = socket.create_connection(
                (tailnet_ipv4(self.target[0]), self.target[1]), timeout=10
            )
            upstream.settimeout(None)
        except OSError:
            client.close()
            return
        back = threading.Thread(target=pump, args=(upstream, client), daemon=True)
        back.start()
        pump(client, upstream)
        back.join()
        client.close()
        upstream.close()

    def close(self) -> None:
        self.listener.close()


def text_result(value: object, error: bool = False) -> dict:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return {"content": [{"type": "text", "text": text}], "isError": error}


class Proxy:
    def __init__(self, config: dict, server: str, launcher: str) -> None:
        self.phones = config["phones"]
        self.port = config["wda"]["port"]
        self.server, self.launcher = server, launcher
        self.write_lock = threading.Lock()
        self.child_lock = threading.Lock()
        self.child: subprocess.Popen | None = None
        self.forward: Forward | None = None
        self.phone: str | None = None
        # Requests forwarded to the current child, by id, so a restart can
        # answer the ones it will never reply to.
        self.pending: dict[object, str] = {}
        self.start_child(None)

    def send(self, message: dict) -> None:
        line = json.dumps(message, ensure_ascii=False)
        with self.write_lock:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()

    def reply(self, ident: object, result: dict) -> None:
        self.send({"jsonrpc": "2.0", "id": ident, "result": result})

    def start_child(self, phone: str | None) -> None:
        """Run iPhone Use for one phone; with none, it only answers the catalog."""
        env = dict(os.environ)
        name = phone or "_unselected"
        if self.forward:
            self.forward.close()
            self.forward = None
        if phone:
            self.forward = Forward(self.phones[phone]["host"], self.port)
            env["WDA_URL"] = f"http://127.0.0.1:{self.forward.port}"
        else:
            env["WDA_URL"] = "http://127.0.0.1:9"
        (STATE / name).mkdir(parents=True, exist_ok=True, mode=0o700)
        env["IPHONE_USE_STATE_DIR"] = str(STATE / name)
        child = subprocess.Popen(
            [self.server],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            env=env,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self.child, self.phone = child, phone
        threading.Thread(target=self.read_child, args=(child,), daemon=True).start()

    def stop_child(self) -> None:
        child, self.child = self.child, None
        if child:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
        if self.forward:
            self.forward.close()
            self.forward = None
        self.abandon_pending("The phone changed before iPhone Use answered; call the tool again.")

    def abandon_pending(self, message: str) -> None:
        pending, self.pending = self.pending, {}
        for ident in pending:
            self.send(
                {"jsonrpc": "2.0", "id": ident, "error": {"code": -32603, "message": message}}
            )

    def read_child(self, child: subprocess.Popen) -> None:
        assert child.stdout
        for line in child.stdout:
            try:
                message = json.loads(line)
            except ValueError:
                continue
            with self.child_lock:
                if child is not self.child:
                    continue
                method = self.pending.pop(message.get("id"), None) if "id" in message else None
            result = message.get("result")
            if method == "tools/list" and isinstance(result, dict):
                tools = [t for t in result.get("tools", []) if t.get("name") not in HIDDEN]
                result["tools"] = self.local_tools() + tools
            elif method == "initialize" and isinstance(result, dict):
                result["instructions"] = INSTRUCTIONS + "\n\n" + result.get("instructions", "")
            self.send(message)
        with self.child_lock:
            if child is self.child:
                self.child = None
                self.abandon_pending("iPhone Use exited; call the tool again to restart it.")

    def local_tools(self) -> list[dict]:
        names = sorted(self.phones)
        phone = {"type": "string", "enum": names}
        return [
            {
                "name": "pua_phones",
                "description": (
                    "List the iPhones this agent can drive and whether each one's "
                    "WebDriverAgent answers now. Ask the user which phone to use, then call "
                    "pua_select_phone; do not choose one yourself unless the user named it."
                ),
                "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
            },
            {
                "name": "pua_select_phone",
                "description": (
                    "Bind every iPhone Use tool in this session to the phone the user chose. "
                    "Call pua_ready next."
                ),
                "inputSchema": {
                    "type": "object",
                    "properties": {"phone": phone},
                    "required": ["phone"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "pua_launch_phone",
                "description": (
                    "Start WebDriverAgent on a phone whose runner does not answer, such as "
                    "after the phone restarted. It works only from a machine that reaches "
                    "the phone's developer services (a Mac paired with it); elsewhere it "
                    "reports which machine can. The phone must be unlocked."
                ),
                "inputSchema": {
                    "type": "object",
                    "properties": {"phone": phone},
                    "required": ["phone"],
                    "additionalProperties": False,
                },
            },
        ]

    def phone_list(self) -> list[dict]:
        listed = []
        for name in sorted(self.phones):
            entry = self.phones[name]
            status = wda_status(entry["host"], self.port)
            listed.append(
                {
                    "phone": name,
                    "description": entry.get("description", ""),
                    "selected": name == self.phone,
                    "answering": bool(status and status.get("ready")),
                    "ios": (status or {}).get("os", {}).get("version"),
                }
            )
        return listed

    def call_local(self, ident: object, name: str, args: dict) -> None:
        if name == "pua_phones":
            self.reply(ident, text_result({"phones": self.phone_list()}))
            return
        phone = args.get("phone")
        if phone not in self.phones:
            self.reply(ident, text_result(f"Unknown phone {phone!r}.", error=True))
            return
        if name == "pua_select_phone":
            with self.child_lock:
                self.stop_child()
                self.start_child(phone)
            status = wda_status(self.phones[phone]["host"], self.port)
            answering = bool(status and status.get("ready"))
            self.reply(
                ident,
                text_result(
                    {
                        "selected": phone,
                        "answering": answering,
                        "next_step": "Call pua_ready."
                        if answering
                        else "The runner does not answer; call pua_launch_phone.",
                    }
                ),
            )
            return
        try:
            run = subprocess.run(
                [self.launcher, "launch", phone],
                capture_output=True,
                text=True,
                timeout=LAUNCH_TIMEOUT,
            )
            output, failed = (run.stdout + run.stderr).strip(), run.returncode != 0
        except subprocess.TimeoutExpired:
            output, failed = f"iphone-wda launch {phone} timed out.", True
        self.reply(ident, text_result(output, error=failed))

    def handle(self, message: dict) -> None:
        method, ident = message.get("method"), message.get("id")
        if method == "tools/call" and ident is not None:
            params = message.get("params") or {}
            name = params.get("name")
            if name in ("pua_phones", "pua_select_phone", "pua_launch_phone"):
                # Launching waits on the phone; keep reading the agent meanwhile.
                threading.Thread(
                    target=self.call_local,
                    args=(ident, name, params.get("arguments") or {}),
                    daemon=True,
                ).start()
                return
            if name in HIDDEN:
                self.reply(
                    ident,
                    text_result(
                        f"{name} is unavailable here: `iphone-wda` launches the runner. "
                        "Use pua_launch_phone.",
                        error=True,
                    ),
                )
                return
            if self.phone is None:
                self.reply(
                    ident,
                    text_result(
                        {
                            "error": "phone_not_selected",
                            "message": "Ask the user which phone to use, then call "
                            "pua_select_phone.",
                            "phones": self.phone_list(),
                        },
                        error=True,
                    ),
                )
                return
        with self.child_lock:
            if self.child is None:
                self.start_child(self.phone)
            child = self.child
            if ident is not None and method:
                self.pending[ident] = method
        assert child.stdin
        try:
            child.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
            child.stdin.flush()
        except OSError:
            with self.child_lock:
                lost = self.pending.pop(ident, None) if ident is not None else None
            if lost:
                self.send(
                    {
                        "jsonrpc": "2.0",
                        "id": ident,
                        "error": {"code": -32603, "message": "iPhone Use exited; call again."},
                    }
                )

    def serve(self) -> None:
        try:
            for line in sys.stdin:
                try:
                    message = json.loads(line)
                except ValueError:
                    continue
                if isinstance(message, dict):
                    self.handle(message)
        finally:
            with self.child_lock:
                self.stop_child()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--server", required=True, help="iPhone Use's MCP server")
    parser.add_argument("--launcher", required=True, help="the iphone-wda command")
    args = parser.parse_args()
    # iPhone Use answers partly in Chinese; MCP stdio is UTF-8 whatever the locale.
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    config = json.loads(CONFIG_PATH.read_text())
    Proxy(config, args.server, args.launcher).serve()


if __name__ == "__main__":
    main()
