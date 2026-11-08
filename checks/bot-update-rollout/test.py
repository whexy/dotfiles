import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

pipeline = yaml.safe_load(Path(sys.argv[1]).read_text())
# The scripts the steps run, copied into each fixture checkout.
scripts = Path(sys.argv[2])
assert {"event": "push", "branch": "master"} in pipeline["when"]
assert "push" in pipeline["steps"]["check"]["when"]["event"]
check = next(
    c
    for c in pipeline["steps"]["check"]["commands"]
    if ".#checks.$system.bot-update-rollout" in c
)
assert ".#packages.$system.dotfiles-upgraded" in check

# An update lane is a step that commits the package updater's work.
lanes = {
    name: step["commands"]
    for name, step in pipeline["steps"].items()
    if any(".#update -- --commit" in c for c in step.get("commands", []))
}
assert lanes, "no step runs .#update -- --commit"

pin = pipeline["steps"]["pin-t3code-fork"]["commands"]
assert pin.index(check) < next(i for i, c in enumerate(pin) if "git push origin HEAD:master" in c)

STUB_NIX = """#!{bash}
echo "nix $*" >> "$CALLS"
case "$*" in
"flake update"*) if [ "$FLAKE_CHANGES" = 1 ]; then echo after > flake.lock; fi; exit 0 ;;
*".#update "*) exit "$UPDATE_STATUS" ;;
*".#flake-lock-diff"*) echo "package report"; exit 0 ;;
*".#github-app-token"*) echo token; exit 0 ;;
esac
case "$1" in
eval) echo fixture ;;
path-info) test "$CACHE_HIT" = 1 ;;
build) test "$CHECK_PASS" = 1 ;;
*) exit 0 ;;
esac
"""

STUB_GIT = """#!{bash}
if [ "$1" = push ]; then echo "git push" >> "$CALLS"; exit 0; fi
if [ "$1" = ls-remote ]; then printf '%s\\trefs/heads/master\\n' "$REMOTE_HEAD"; exit 0; fi
exec {git} "$@"
"""


def run(script, cwd, env):
    return subprocess.run(
        ["bash", "-eu", "-o", "pipefail", "-c", script],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
    )


def fixture(directory):
    root = Path(directory)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    for name, stub in (("nix", STUB_NIX), ("git", STUB_GIT)):
        path = bin_dir / name
        path.write_text(stub.format(bash=shutil.which("bash"), git=shutil.which("git")))
        path.chmod(0o755)
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
    env.update(
        HOME=directory,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_CONFIG_GLOBAL=str(root / "gitconfig"),
        CALLS=str(root / "calls"),
        CI_CACHE_ENDPOINT="https://cache.invalid",
        CI_PIPELINE_FILES='["flake.lock"]',
        NIX_CACHE_SIGNING_KEY="fixture",
        NIX_CONFIG="",
        REX_PACKAGE_TOKEN="fixture",
        CACHE_HIT="1",
        CHECK_PASS="0",
    )
    repo = root / "repo"
    repo.mkdir()
    shutil.copytree(scripts, repo / "ci")
    setup = (
        "git init -q && git config core.hooksPath /dev/null"
        " && git config user.name fixture && git config user.email fixture@example.invalid"
        " && git remote add origin https://example.invalid/repo.git"
        " && echo before > flake.lock && git add . && git commit -qm initial"
    )
    assert run(setup, repo, env).returncode == 0
    return root, repo, env


for lane, commands in lanes.items():
    assert check in commands
    push = next(i for i, c in enumerate(commands) if "git push origin HEAD:master" in c)
    assert commands.index(check) < push  # check before push
    script = "\n".join(commands)

    # Each failing package is reverted by the driver; the lane still pushes
    # what did update, then fails so report-failure runs.
    for flake_changes, status in (("1", "0"), ("1", "1"), ("0", "0"), ("0", "1")):
        with tempfile.TemporaryDirectory() as directory:
            root, repo, env = fixture(directory)
            env.update(FLAKE_CHANGES=flake_changes, UPDATE_STATUS=status)
            result = run(script, repo, env)
            calls = (root / "calls").read_text()
            assert (result.returncode == 0) == (status == "0"), (lane, result.stderr)
            assert ("git push" in calls) == (flake_changes == "1"), (lane, calls)
            assert ("nix path-info" in calls) == (flake_changes == "1"), (lane, calls)
            if flake_changes == "1":
                message = run("git log -1 --format=%B", repo, env).stdout.lower()
                assert "[skip ci]" not in message and "[ci skip]" not in message, message
                assert "package report" in message, message

    with tempfile.TemporaryDirectory() as directory:
        root, repo, env = fixture(directory)
        for hit, passes, expected in (("1", "0", 0), ("0", "1", 0), ("0", "0", 1)):
            (root / "calls").write_text("")
            result = run(check, repo, dict(env, CACHE_HIT=hit, CHECK_PASS=passes))
            assert (result.returncode == 0) == (expected == 0), result.stderr
            calls = (root / "calls").read_text()
            assert ("build " in calls) == (hit == "0"), calls
    print(f"{lane}: push enabled, failed updates still pushed, cached success reused, failed checks rejected")

# The announcement is the push pipeline's last passing step: it runs only on
# master pushes, after every other step, and announces only the tip.
names = list(pipeline["steps"])
announce = pipeline["steps"]["announce"]
assert announce["when"] == {"event": "push", "branch": "master"}, announce["when"]
assert not any("depends_on" in step for step in pipeline["steps"].values())
assert names.index("announce") == names.index("report-failure") - 1, names
for name in ("check", "build-docs", "deploy-docs"):
    assert names.index(name) < names.index("announce"), name
script = "\n".join(announce["commands"])
for head, announced in (("a" * 40, True), ("b" * 40, False)):
    with tempfile.TemporaryDirectory() as directory:
        root, repo, env = fixture(directory)
        env.update(REMOTE_HEAD=head, CI_COMMIT_SHA="a" * 40, CI_PIPELINE_NUMBER="42")
        result = run(script, repo, env)
        assert result.returncode == 0, result.stderr
        calls = (root / "calls").read_text() if (root / "calls").exists() else ""
        assert ("announce" in calls) == announced, calls
        if announced:
            assert "--sha " + "a" * 40 in calls and "--seq 42" in calls, calls
print("announce: last step on master pushes, tip only")
