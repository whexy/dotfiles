"""Run a package's update.py for the ``script`` kind: its ``main()``, which
ends the run with the package's name and the message of any UpdateError."""

import os
import runpy
import sys

from . import UpdateError


def run(path: str, name: str) -> None:
    script = runpy.run_path(path, run_name="update")
    try:
        script["main"]()
    except UpdateError as error:
        sys.exit(f"{name}: {error}")


if __name__ == "__main__":
    run(sys.argv[1], os.environ["UPDATE_PACKAGE"])
