import runpy
import tempfile
import unittest
from pathlib import Path

from updater import UpdateError, kinds, script
from updater.package import Package

# The packages directory, which holds each package's update.py.
PACKAGES = Path(__file__).resolve().parents[2]

FAILING = """from updater import UpdateError


def main():
    raise UpdateError("no release")
"""


class ScriptTest(unittest.TestCase):
    def test_scripts_import(self):
        """Every update.py imports what it uses from the updater and has main()."""
        scripts = sorted(PACKAGES.glob("*/update.py"))
        self.assertTrue(scripts, f"no update.py under {PACKAGES}")
        for path in scripts:
            with self.subTest(package=path.parent.name):
                self.assertTrue(callable(runpy.run_path(str(path), run_name="update")["main"]))

    def test_update_error_names_the_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "packages" / "demo" / "update.py"
            path.parent.mkdir(parents=True)
            path.write_text(FAILING)
            with self.assertRaises(SystemExit) as exited:
                script.run(str(path), "demo")
            self.assertEqual(exited.exception.code, "demo: no release")

            pkg = Package(name="demo", version="1", system="x86_64-linux", root=Path(tmp))
            with self.assertRaises(UpdateError) as raised:
                kinds.script(pkg, {})
            self.assertIn("exited 1", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
