import unittest

import flake_lock_diff as fld


def drv(name, inputs=(), fixed=False):
    outputs = {"out": {"hash": "sha256-x", "method": "flat"} if fixed else {}}
    return {
        "name": name,
        "inputs": {"drvs": {p: {"outputs": ["out"]} for p in inputs}},
        "outputs": outputs,
    }


class FakeStore:
    def __init__(self, drvs):
        self.drvs = drvs
        self.calls = []

    def show(self, paths):
        self.calls.append(paths)
        return {
            "version": 4,
            "derivations": {p: self.drvs[p] for p in paths},
        }


class SplitNameTest(unittest.TestCase):
    def test_versions(self):
        self.assertEqual(fld.split_name("firefox-157.0"), ("firefox", "157.0"))
        self.assertEqual(
            fld.split_name("python3.13-requests-2.32.3"),
            ("python3.13-requests", "2.32.3"),
        )
        self.assertEqual(fld.split_name("home-manager-path"), ("home-manager-path", None))


class GraphTest(unittest.TestCase):
    def setUp(self):
        self.store = FakeStore(
            {
                "r-nixos-system-host-26.05.drv": drv(
                    "nixos-system-host-26.05", ["e-etc.drv", "u-unit-nginx.service.drv"]
                ),
                "e-etc.drv": drv("etc", ["s-stdenv-linux.drv", "g-ghostty-1.3.1.drv"]),
                "u-unit-nginx.service.drv": drv("unit-nginx.service", ["n-nginx-1.28.0.drv"]),
                "s-stdenv-linux.drv": drv("stdenv-linux", ["c-gcc-wrapper-15.drv"]),
                "c-gcc-wrapper-15.drv": drv("gcc-wrapper-15"),
                "g-ghostty-1.3.1.drv": drv("ghostty-1.3.1", ["z-zig-0.15.drv"]),
                "z-zig-0.15.drv": drv("zig-0.15"),
                "n-nginx-1.28.0.drv": drv("nginx-1.28.0", ["t-nginx-1.28.0.tar.gz.drv"]),
                "t-nginx-1.28.0.tar.gz.drv": drv("nginx-1.28.0.tar.gz", fixed=True),
            }
        )
        self.graph = fld.Graph(show=self.store.show)

    def test_stops_at_versioned_derivations(self):
        found = self.graph.packages("/nix/store/r-nixos-system-host-26.05.drv")
        # zig and the nginx tarball sit behind packages; gcc behind stdenv.
        self.assertEqual(found, {"ghostty": {"1.3.1"}, "nginx": {"1.28.0"}})

    def test_reuses_fetched_derivations(self):
        self.graph.packages("r-nixos-system-host-26.05.drv")
        calls = len(self.store.calls)
        self.graph.packages("r-nixos-system-host-26.05.drv")
        self.assertEqual(len(self.store.calls), calls)

    def test_reads_legacy_derivation_show(self):
        legacy = {
            "/nix/store/a-etc.drv": {
                "name": "etc",
                "inputDrvs": {"/nix/store/b-bat-0.26.drv": ["out"]},
                "outputs": {"out": {"path": "/nix/store/x-etc"}},
            },
            "/nix/store/b-bat-0.26.drv": {
                "name": "bat-0.26",
                "inputDrvs": {},
                "outputs": {"out": {"path": "/nix/store/y-bat"}},
            },
        }
        graph = fld.Graph(show=lambda paths: {"/nix/store/" + p: legacy["/nix/store/" + p] for p in paths})
        self.assertEqual(graph.packages("/nix/store/a-etc.drv"), {"bat": {"0.26"}})


class ReportTest(unittest.TestCase):
    def test_groups_changes_across_hosts(self):
        per_root = {
            "a": ({"fx": {"1"}, "old": {"2"}}, {"fx": {"2"}}),
            "b": ({"fx": {"1"}}, {"fx": {"2"}, "new": {"3"}}),
        }
        grouped = fld.group_changes(per_root)
        self.assertEqual(
            grouped,
            {
                ("updated", "fx", ("1",), ("2",)): ["a", "b"],
                ("removed", "old", ("2",), ()): ["a"],
                ("added", "new", (), ("3",)): ["b"],
            },
        )
        text = fld.report([], grouped, [])
        self.assertIn("Updated:\n  fx  1 -> 2  a, b", text)
        self.assertIn("Added:\n  new  3  b", text)
        self.assertIn("Removed:\n  old  2  a", text)

    def test_reports_input_changes(self):
        def lock(rev, stamp):
            return {
                "root": "root",
                "nodes": {
                    "root": {"inputs": {"nixpkgs": "nixpkgs", "x": ["nixpkgs"]}},
                    "nixpkgs": {"locked": {"rev": rev, "lastModified": stamp}},
                },
            }

        inputs = list(fld.input_changes(lock("aaaaaaaa1", 0), lock("bbbbbbbb2", 86400)))
        self.assertEqual(
            inputs, [("nixpkgs", ("aaaaaaa", "1970-01-01"), ("bbbbbbb", "1970-01-02"))]
        )
        text = fld.report(inputs, {}, [("darwin", "old", "boom")])
        self.assertIn("nixpkgs  aaaaaaa -> bbbbbbb  (1970-01-01 -> 1970-01-02)", text)
        self.assertIn("No package version changes.", text)
        self.assertIn("darwin (old lock): boom", text)


if __name__ == "__main__":
    unittest.main()
