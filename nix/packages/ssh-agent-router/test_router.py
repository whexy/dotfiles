import concurrent.futures
import contextlib
import errno
import os
from pathlib import Path
import signal
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

import router


class Agent:
    def __init__(self, path, label):
        self.path = path
        self.label = label
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(path))
        self.listener.listen()
        self.listener.settimeout(0.1)
        self.stopped = threading.Event()
        self.connections = []
        self.thread = threading.Thread(target=self.accept, daemon=True)
        self.thread.start()

    def accept(self):
        while not self.stopped.is_set():
            try:
                client, _ = self.listener.accept()
            except TimeoutError:
                continue
            except OSError:
                return
            self.connections.append(client)
            threading.Thread(target=self.respond, args=(client,), daemon=True).start()

    def respond(self, client):
        with client:
            try:
                while data := client.recv(65536):
                    client.sendall(self.label + data)
            except OSError:
                pass

    def close(self, unlink=True):
        self.stopped.set()
        self.listener.close()
        self.thread.join(timeout=2)
        for client in self.connections:
            with contextlib.suppress(OSError):
                client.shutdown(socket.SHUT_RDWR)
        if unlink:
            self.path.unlink(missing_ok=True)


class RouterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="agent-router-")
        self.home = Path(self.temporary.name)
        self.state = self.home / ".ssh/agent-router"
        self.proxy = self.home / ".ssh/ssh-agent.sock"
        self.env = dict(
            os.environ, HOME=str(self.home), SSH_CONNECTION="test-connection"
        )
        for name in ("SSH_AUTH_SOCK", "TMUX", "ZELLIJ"):
            self.env.pop(name, None)
        self.agents = []

    def tearDown(self):
        for agent in self.agents:
            agent.close()
        self.stop_daemon()
        self.temporary.cleanup()

    def stop_daemon(self):
        lock_path = self.state / "daemon.lock"
        if lock_path.exists() and lock_path.read_text().strip():
            with contextlib.suppress(ProcessLookupError):
                os.kill(int(lock_path.read_text()), signal.SIGTERM)
            # Blocking flock synchronizes with process exit, not an arbitrary sleep.
            with router.lock_file(lock_path) as lock:
                router.fcntl.flock(lock, router.fcntl.LOCK_EX)
            lock_path.write_text("")

    def agent(self, label):
        agent = Agent(self.home / f"agent-{len(self.agents)}", label)
        self.agents.append(agent)
        return agent

    def command(self, *args, **env):
        return subprocess.run(
            [sys.executable, router.__file__, *args],
            env=dict(self.env, **env),
            capture_output=True,
            text=True,
            timeout=10,
        )

    def register(self, agent):
        result = self.command("register", str(agent.path))
        self.assertEqual(result.returncode, 0, result.stderr)

    def connect(self):
        client = socket.socket(socket.AF_UNIX)
        client.settimeout(3)
        client.connect(str(self.proxy))
        return client

    def request(self, expected):
        with self.connect() as client:
            client.sendall(b"request")
            self.assertEqual(client.recv(1024), expected + b"request")

    def test_newest_and_fallback_both_disconnect_orders(self):
        office = self.agent(b"office:")
        laptop = self.agent(b"laptop:")
        self.register(office)
        self.register(laptop)
        self.request(b"laptop:")
        laptop.close(unlink=False)
        self.request(b"office:")
        office.close()
        with self.connect() as client:
            client.sendall(b"request")
            try:
                self.assertEqual(client.recv(1024), b"")
            except ConnectionResetError:
                pass
        reconnect = self.agent(b"reconnected:")
        self.register(reconnect)
        self.request(b"reconnected:")
        newer = self.agent(b"newer:")
        self.register(newer)
        reconnect.close()
        self.request(b"newer:")

    def test_duplicates_do_not_promote_and_connections_are_pinned(self):
        office = self.agent(b"office:")
        laptop = self.agent(b"laptop:")
        self.register(office)
        with self.connect() as client:
            client.sendall(b"first")
            self.assertEqual(client.recv(1024), b"office:first")
            self.register(laptop)
            self.register(office)
            client.sendall(b"second")
            self.assertEqual(client.recv(1024), b"office:second")
            # Another active conversation must not wait for this one to close.
            self.request(b"laptop:")
        self.assertEqual(len(router.read_agents(self.state)), 2)

    def test_denial_is_relayed_without_fallback(self):
        office = self.agent(b"office:")
        denied = self.agent(b"denied:")
        self.register(office)
        self.register(denied)
        self.request(b"denied:")
        self.assertEqual(len(office.connections), 0)

    def test_permissions_and_legacy_symlink_migration(self):
        agent = self.agent(b"agent:")
        self.proxy.parent.mkdir(mode=0o700)
        self.proxy.symlink_to(agent.path)
        self.register(agent)
        self.assertFalse(self.proxy.is_symlink())
        self.assertEqual(self.proxy.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        self.request(b"agent:")
        result = self.command("register", str(self.proxy))
        self.assertNotEqual(result.returncode, 0)

    def test_shell_affinity_and_multiplexer_selection(self):
        agent = self.agent(b"agent:")
        ordinary = self.command("shell", SSH_AUTH_SOCK=str(agent.path))
        self.assertEqual(ordinary.returncode, 0, ordinary.stderr)
        self.assertEqual(ordinary.stdout.strip(), str(agent.path))
        for variable in ("TMUX", "ZELLIJ"):
            pane = self.command(
                "shell", SSH_AUTH_SOCK=str(agent.path), **{variable: "session"}
            )
            self.assertEqual(pane.returncode, 0, pane.stderr)
            self.assertEqual(pane.stdout.strip(), str(self.proxy))
        local = self.command(
            "shell", SSH_CONNECTION="", SSH_AUTH_SOCK="/local/1password"
        )
        self.assertEqual(local.stdout.strip(), "/local/1password")
        nested = self.command("shell", SSH_AUTH_SOCK=str(agent.path))
        self.assertEqual(nested.returncode, 0, nested.stderr)
        self.assertEqual(len(router.read_agents(self.state)), 1)

    def test_concurrent_registration_and_daemon_restart(self):
        agents = [self.agent(str(index).encode()) for index in range(4)]
        with concurrent.futures.ThreadPoolExecutor() as executor:
            list(executor.map(self.register, agents))
        records = router.read_agents(self.state)
        self.assertEqual(len(records), 4)
        newest = next(
            agent for agent in agents if str(agent.path) == records[-1]["path"]
        )
        self.request(newest.label)
        self.stop_daemon()
        self.register(agents[0])
        self.assertEqual(router.read_agents(self.state), records)
        self.request(newest.label)

    def test_permission_failure_does_not_fall_back(self):
        agent = self.agent(b"agent:")
        self.register(agent)
        with mock.patch.object(
            socket.socket,
            "connect",
            side_effect=PermissionError(errno.EACCES, "denied"),
        ):
            with self.assertRaises(PermissionError):
                router.connect_upstream(self.state)
        self.assertEqual(len(router.read_agents(self.state)), 1)

    def test_refuses_non_socket_and_unsafe_state(self):
        file = self.home / "not-a-socket"
        file.write_text("keep")
        self.assertNotEqual(self.command("register", str(file)).returncode, 0)
        self.assertEqual(file.read_text(), "keep")
        unsafe = self.home / "unsafe"
        unsafe.symlink_to(self.state)
        with self.assertRaises(ValueError):
            router.private_directory(unsafe)

    @unittest.skipUnless(shutil.which("ssh-agent"), "OpenSSH is not installed")
    def test_real_openssh_signing_and_empty_agent_no_fallback(self):
        processes = []
        try:
            for index in range(2):
                path = self.home / f"real-agent-{index}"
                key = self.home / f"key-{index}"
                subprocess.run(
                    [
                        "ssh-keygen",
                        "-q",
                        "-t",
                        "ed25519",
                        "-N",
                        "",
                        "-C",
                        f"key-{index}",
                        "-f",
                        str(key),
                    ],
                    check=True,
                    capture_output=True,
                )
                process = subprocess.Popen(
                    ["ssh-agent", "-D", "-a", str(path)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                processes.append(process)
                # ssh-agent publishes its environment only after binding its socket.
                self.assertTrue(router.select.select([process.stdout], [], [], 5)[0])
                self.assertIn(b"SSH_AUTH_SOCK", process.stdout.readline())
                environment = dict(self.env, SSH_AUTH_SOCK=str(path))
                subprocess.run(
                    ["ssh-add", str(key)],
                    env=environment,
                    check=True,
                    capture_output=True,
                )
                result = self.command("register", str(path))
                self.assertEqual(result.returncode, 0, result.stderr)
            environment = dict(self.env, SSH_AUTH_SOCK=str(self.proxy))
            message = self.home / "message"
            message.write_text("agent routing integration test\n")
            result = subprocess.run(
                [
                    "ssh-keygen",
                    "-Y",
                    "sign",
                    "-n",
                    "git",
                    "-f",
                    str(key) + ".pub",
                    str(message),
                ],
                env=environment,
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            allowed = self.home / "allowed-signers"
            allowed.write_text("test " + Path(str(key) + ".pub").read_text())
            result = subprocess.run(
                [
                    "ssh-keygen",
                    "-Y",
                    "verify",
                    "-n",
                    "git",
                    "-I",
                    "test",
                    "-f",
                    str(allowed),
                    "-s",
                    str(message) + ".sig",
                ],
                input=message.read_bytes(),
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            subprocess.run(
                ["ssh-add", "-D"], env=environment, check=True, capture_output=True
            )
            result = subprocess.run(
                ["ssh-add", "-l"], env=environment, capture_output=True, timeout=5
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn(b"no identities", result.stdout)
            processes[-1].terminate()
            processes[-1].wait(timeout=5)
            result = subprocess.run(
                ["ssh-add", "-l"], env=environment, capture_output=True, timeout=5
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b"key-0", result.stdout)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
                process.stdout.close()
                process.stderr.close()


if __name__ == "__main__":
    unittest.main()
