"""The manimgx command: ManimGX's CLI, ended before the C runtime's teardown.

The engine keeps its wgpu device for the whole process and never destroys
it. NVIDIA's Vulkan driver then races its own "[vkps] Update" thread
against the exit handlers that unload it, so a finished render can still
die with SIGSEGV (seen with driver 575 on the A100s). Once Python has done
its own cleanup, ending with os._exit skips that teardown.
"""

import atexit
import os
import sys
import threading

from manimgx.cli import main as cli


def main() -> None:
    try:
        cli()
        code = 0
    except SystemExit as stop:
        code = stop.code
    except BaseException:
        sys.excepthook(*sys.exc_info())
        code = 1
    if code is None:
        code = 0
    elif not isinstance(code, int):
        print(code, file=sys.stderr)
        code = 1
    for thread in threading.enumerate():
        if thread is not threading.main_thread() and not thread.daemon:
            thread.join()
    atexit._run_exitfuncs()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)
