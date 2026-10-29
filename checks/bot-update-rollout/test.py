import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile

import yaml

pipeline = yaml.safe_load(Path(sys.argv[1]).read_text())
assert {"event": "push", "branch": "master"} in pipeline["when"]
assert "push" in pipeline["steps"]["check"]["when"]["event"]
assert ".#packages.$system.dotfiles-upgraded" in pipeline["steps"]["check"]["commands"][0]
assert ".#checks.$system.bot-update-rollout" in pipeline["steps"]["check"]["commands"][0]


def run(script, cwd, env):
    return subprocess.run(
        ["bash", "-eu", "-o", "pipefail", "-c", script],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        timeout=10,
    )


for lane in ("update-flake", "update-nightly-agents"):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        nix = bin_dir / "nix"
        nix.write_text(
            f'#!{shutil.which("bash")}\n'
            'echo "$*" >> "$CALLS"\n'
            'case "$1" in\n'
            'run) echo "package report" ;;\n'
            'eval) echo "fixture" ;;\n'
            'path-info) test "$CACHE_HIT" = 1 ;;\n'
            'build) test "$CHECK_PASS" = 1 ;;\n'
            '*) exit 0 ;;\n'
            'esac\n'
        )
        nix.chmod(0o755)
        env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
        env.update(
            HOME=directory,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL="/dev/null",
            GIT_AUTHOR_NAME="fixture",
            GIT_AUTHOR_EMAIL="fixture@example.invalid",
            GIT_COMMITTER_NAME="fixture",
            GIT_COMMITTER_EMAIL="fixture@example.invalid",
            CALLS=str(root / "calls"),
            CI_CACHE_ENDPOINT="https://cache.invalid",
            CI_PIPELINE_FILES='["flake.lock"]',
            NIX_CACHE_SIGNING_KEY="fixture",
        )
        assert run("git init -q && git config core.hooksPath /dev/null", root, env).returncode == 0
        (root / "flake.lock").write_text("before")
        assert run("git add . && git commit -qm initial", root, env).returncode == 0
        (root / "flake.lock").write_text("after")
        metadata = root / "packages/t3code-nightly/metadata.nix"
        metadata.parent.mkdir(parents=True)
        metadata.write_text("{}")
        commands = pipeline["steps"][lane]["commands"]
        commit = next(c for c in commands if "git commit -m" in c)
        result = run(commit, root, env)
        assert result.returncode == 0, result.stderr
        message = run("git log -1 --format=%B", root, env).stdout.lower()
        assert "[skip ci]" not in message and "[ci skip]" not in message, message
        check = pipeline["steps"]["check"]["commands"][0]
        assert check in commands
        assert commands.index(check) < len(commands) - 1  # check before push
        for hit, passes, expected in (("1", "0", 0), ("0", "1", 0), ("0", "0", 1)):
            (root / "calls").write_text("")
            result = run(check, root, dict(env, CACHE_HIT=hit, CHECK_PASS=passes))
            assert (result.returncode == 0) == (expected == 0), result.stderr
            calls = (root / "calls").read_text()
            assert ("build " in calls) == (hit == "0"), calls
        print(f"{lane}: push enabled, cached success reused, failed checks rejected")
