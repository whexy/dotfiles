import base64
import os
import select
import signal
import subprocess
import sys
import tempfile
from urllib.parse import quote

import msgpack


class Connection:
    def __init__(self, url):
        self.process = subprocess.Popen(
            [sys.argv[1], '--stdio-url-base64', base64.b64encode(url.encode()).decode(), '--embed'],
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
    os.environ['XDG_RUNTIME_DIR'] = root
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

    for bad in ['--help', 'vscode://vscode-remote/ssh-remote+host',
                'vscode://vscode-remote/ssh-remote+-oProxyCommand=bad/tmp',
                'vscode://vscode-remote/ssh-remote+host/tmp%00bad',
                'vscode://vscode-remote/ssh-remote+host/tmp%ZZ']:
        result = subprocess.run(
            [sys.argv[1], '--stdio-url-base64', base64.b64encode(bad.encode()).decode(), '--embed'],
            capture_output=True, timeout=10,
        )
        assert result.returncode != 0
        assert result.stdout == b'', result.stdout
print('RPC relay, concurrent tunnels, session reuse, cleanup, and URL validation passed')
