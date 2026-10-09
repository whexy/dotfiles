import base64
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
from urllib.parse import quote

import msgpack


def command(url):
    return [sys.argv[1], '--stdio-url-base64', base64.b64encode(url.encode()).decode(), '--embed']


class Connection:
    def __init__(self, url, env=None):
        self.process = subprocess.Popen(
            command(url), env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.messages = msgpack.Unpacker(raw=False)

    def call(self, method, *args):
        self.process.stdin.write(msgpack.packb([0, 1, method, list(args)], use_bin_type=True))
        self.process.stdin.flush()
        while True:
            for message in self.messages:
                if message[:2] == [1, 1]:
                    assert message[2] is None, message
                    return message[3]
            ready, _, _ = select.select([self.process.stdout], [], [], 15)
            assert ready, 'RPC timed out'
            data = os.read(self.process.stdout.fileno(), 65536)
            assert data, self.process.stderr.read().decode()
            self.messages.feed(data)

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=10) == 0, self.process.stderr.read().decode()


with tempfile.TemporaryDirectory() as root:
    runtime = os.path.join(root, 'runtime')
    sockets = os.path.join(root, 'tmp')
    os.mkdir(runtime)
    os.mkdir(sockets)
    os.environ['XDG_RUNTIME_DIR'] = runtime
    os.environ['TMPDIR'] = sockets
    folder = os.path.join(root, "folder with ' quotes \\ and 日本語")
    os.mkdir(folder)
    url = 'vscode://vscode-remote/ssh-remote+test-host' + quote(folder)
    connections = []
    pid = None
    try:
        first = Connection(url)
        connections.append(first)
        pid = first.call('nvim_eval', 'getpid()')
        assert first.call('nvim_eval', 'getcwd()') == folder
        first.call('nvim_set_var', 'relay_test', 'survives disconnect')
        second = Connection(url)
        connections.append(second)
        assert second.call('nvim_eval', 'getpid()') == pid
        first.close()
        connections.remove(first)
        assert second.call('nvim_get_var', 'relay_test') == 'survives disconnect'
        second.close()
        connections.remove(second)
        # Logind wipes the runtime dir at logout, while nvim keeps running.
        shutil.rmtree(runtime)
        os.mkdir(runtime)
        third = Connection(url)
        connections.append(third)
        assert third.call('nvim_eval', 'getpid()') == pid
        assert third.call('nvim_get_var', 'relay_test') == 'survives disconnect'
        third.close()
        connections.remove(third)
    finally:
        for connection in connections:
            connection.process.kill()
            connection.process.wait()
        if pid:
            os.kill(pid, signal.SIGTERM)

    # Whoever owns the socket directory can serve the session to its user.
    for unsafe in ['world-writable', 'symlink']:
        tmp = os.path.join(root, unsafe)
        os.mkdir(tmp)
        planted = os.path.join(tmp, f'neovide-remote-{os.getuid()}')
        if unsafe == 'symlink':
            os.mkdir(planted + '.target', 0o700)
            os.symlink(planted + '.target', planted)
        else:
            os.mkdir(planted)
            os.chmod(planted, 0o777)
        result = subprocess.run(command(url), capture_output=True, timeout=10,
                                env=dict(os.environ, TMPDIR=tmp))
        assert result.returncode != 0, unsafe
        assert result.stdout == b'', result.stdout
        assert os.listdir(planted) == [], os.listdir(planted)

    for bad in ['--help', 'vscode://vscode-remote/ssh-remote+host',
                'vscode://vscode-remote/ssh-remote+-oProxyCommand=bad/tmp',
                'vscode://vscode-remote/ssh-remote+host/tmp%00bad',
                'vscode://vscode-remote/ssh-remote+host/tmp%ZZ']:
        result = subprocess.run(command(bad), capture_output=True, timeout=10)
        assert result.returncode != 0
        assert result.stdout == b'', result.stdout

    # `wsl.exe --exec` gives no login PATH: a plain nvim must still start, and
    # the profile's nvim must beat a distro one.
    def fake_nvim(directory):
        os.makedirs(directory)
        with open(os.path.join(directory, 'nvim'), 'w') as wrapper:
            wrapper.write(f'#!{shutil.which("sh")}\nexport NVIM_FROM={directory}\n'
                          f'exec {shutil.which("nvim")} "$@"\n')
        os.chmod(os.path.join(directory, 'nvim'), 0o755)

    document = os.path.join(root, 'document.txt')
    open(document, 'w').close()
    home = os.path.join(root, 'home')
    distro = os.path.join(root, 'distro')
    profile = os.path.join(home, '.nix-profile', 'bin')
    env = dict(os.environ, HOME=home, PATH=distro)
    env.pop('XDG_STATE_HOME', None)
    for expected in ['', profile]:
        if expected:
            fake_nvim(distro)
            fake_nvim(profile)
        embedded = Connection('vscode://file' + quote(document), env)
        try:
            assert embedded.call('nvim_buf_get_name', 0) == document
            assert embedded.call('nvim_eval', '$NVIM_FROM') == expected
        finally:
            embedded.process.kill()
            embedded.process.wait()
print('RPC relay, concurrent tunnels, session reuse, private sockets, cleanup, URL validation, and local files passed')
