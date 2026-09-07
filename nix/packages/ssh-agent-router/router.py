#!/usr/bin/env python3
"""Newest-live SSH agent routing for persistent terminal sessions."""

import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import select
import socket
import stat
import subprocess
import sys
import threading


def locations():
    home = Path.home()
    return home / ".ssh/agent-router", home / ".ssh/ssh-agent.sock"


def private_directory(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError(f"Unsafe runtime directory: {path}")
    path.chmod(0o700)


def socket_identity(path):
    info = os.stat(path)
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError(f"Not a socket owned by this user: {path}")
    return {"path": str(path), "dev": info.st_dev, "ino": info.st_ino}


def read_agents(state):
    try:
        return json.loads((state / "agents.json").read_text())
    except FileNotFoundError:
        return []


def write_agents(state, agents):
    temporary = state / "agents.json.tmp"
    temporary.write_text(json.dumps(agents))
    temporary.replace(state / "agents.json")


def lock_file(path):
    return path.open("a+")


def register(state, proxy, upstream=None):
    private_directory(state)
    with lock_file(state / "registry.lock") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if upstream is not None:
            # The legacy shared symlink must never become an upstream to itself.
            if Path(upstream) == proxy or Path(upstream).resolve() == proxy:
                raise ValueError("Cannot register the proxy as an upstream")
            identity = socket_identity(upstream)
            agents = read_agents(state)
            if identity not in agents:
                agents = [agent for agent in agents if agent["path"] != upstream]
                agents.append(identity)
                write_agents(state, agents)
        ensure_daemon(state, proxy)


def ensure_daemon(state, proxy):
    with lock_file(state / "daemon.lock") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        with (state / "daemon.log").open("ab") as log:
            child = subprocess.Popen(
                [sys.executable, __file__, "serve", str(lock.fileno())],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=log,
                pass_fds=(lock.fileno(),),
                start_new_session=True,
            )
        try:
            ready, _, _ = select.select([child.stdout], [], [], 5)
            if not ready or child.stdout.readline() != b"ready\n":
                raise RuntimeError(
                    f"Agent router failed to start; see {state / 'daemon.log'}"
                )
        except BaseException:
            child.terminate()
            child.wait()
            raise
        finally:
            child.stdout.close()
        # The inherited descriptor keeps the flock held for the daemon's lifetime.


def connect_upstream(state):
    with lock_file(state / "registry.lock") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        agents = read_agents(state)
        for agent in reversed(agents.copy()):
            upstream = socket.socket(socket.AF_UNIX)
            try:
                if socket_identity(agent["path"]) != agent:
                    raise FileNotFoundError("Socket identity changed")
                upstream.settimeout(1)
                upstream.connect(agent["path"])
                upstream.settimeout(None)
            except (OSError, ValueError) as error:
                upstream.close()
                # Only definitive disappearance is evicted. Busy or denied agents
                # must not silently send authorization to another laptop.
                if (
                    isinstance(error, OSError)
                    and error.errno in (errno.ENOENT, errno.ECONNREFUSED, errno.ENOTDIR)
                    or isinstance(error, FileNotFoundError)
                ):
                    agents.remove(agent)
                    write_agents(state, agents)
                    continue
                raise
            return upstream
    raise ConnectionError("No live forwarded SSH agents")


def relay(client, upstream):
    # Keep the entire byte stream on one agent; never replay a signing request.
    readers = [client, upstream]
    while readers:
        ready, _, _ = select.select(readers, [], [])
        for source in ready:
            destination = upstream if source is client else client
            data = source.recv(65536)
            if data:
                destination.sendall(data)
            else:
                readers.remove(source)
                destination.shutdown(socket.SHUT_WR)


def handle_client(client, state):
    with client:
        try:
            with connect_upstream(state) as upstream:
                relay(client, upstream)
        except (OSError, ValueError) as error:
            print(f"Agent connection closed: {error}", file=sys.stderr, flush=True)


def serve(state, proxy, lock_fd):
    os.ftruncate(lock_fd, 0)
    os.write(lock_fd, f"{os.getpid()}\n".encode())
    os.umask(0o077)
    if proxy.is_symlink() or proxy.exists():
        info = proxy.lstat()
        if info.st_uid != os.getuid() or not (
            stat.S_ISSOCK(info.st_mode) or stat.S_ISLNK(info.st_mode)
        ):
            raise ValueError(f"Refusing to replace {proxy}")
        proxy.unlink()
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(str(proxy))
        listener.listen(64)
        print("ready", flush=True)
        sys.stdout.close()
        while True:
            client, _ = listener.accept()
            threading.Thread(
                target=handle_client, args=(client, state), daemon=True
            ).start()


def shell_socket():
    state, proxy = locations()
    current = os.environ.get("SSH_AUTH_SOCK", "")
    if not os.environ.get("SSH_CONNECTION"):
        return current
    if os.environ.get("TMUX") or os.environ.get("ZELLIJ"):
        register(state, proxy)
        return str(proxy)
    if current and Path(current) != proxy:
        register(state, proxy, current)
    return current


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["shell", "has-agent", "register", "serve"])
    parser.add_argument("argument", nargs="?")
    args = parser.parse_args()
    state, proxy = locations()
    try:
        if args.command == "shell":
            print(shell_socket())
        elif args.command == "has-agent":
            # Only an inbound SSH session carries a forwarded or proxied agent.
            # A local desktop's SSH_AUTH_SOCK belongs to another agent (gcr,
            # gpg-agent) and must not displace the 1Password IdentityAgent.
            forwarded = os.environ.get("SSH_CONNECTION") and os.environ.get(
                "SSH_AUTH_SOCK"
            )
            return 0 if forwarded else 1
        elif args.command == "register":
            if not args.argument:
                parser.error("register requires a socket path")
            register(state, proxy, args.argument)
        else:
            serve(state, proxy, int(args.argument))
    except (OSError, ValueError, RuntimeError) as error:
        print(f"ssh-agent-router: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
