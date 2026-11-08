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
steps = pipeline["steps"]
assert {"event": "push", "branch": "master"} in pipeline["when"]
assert "push" in steps["check"]["when"]["event"]
check = "bash ci/check.sh"
for name in ("check", "check-pr"):
    assert check in steps[name]["commands"], name

# An update lane is a step that runs ci/update.sh.
lanes = {
    name: step["commands"]
    for name, step in steps.items()
    if "bash ci/update.sh" in step.get("commands", [])
}
assert lanes, "no step runs ci/update.sh"
pin = steps["pin-t3code-fork"]["commands"]
assert "bash ci/pin-t3code-fork.sh" in pin

STUB_NIX = """#!{bash}
echo "nix $*" >> "$CALLS"
case "$*" in
"flake update"*) if [ "$FLAKE_CHANGES" = 1 ]; then echo after > flake.lock; fi; exit 0 ;;
*".#update "*) exit "$UPDATE_STATUS" ;;
*".#flake-lock-diff"*) echo "package report"; exit 0 ;;
*".#github-app-token"*) echo token; exit 0 ;;
*"--dry-run"*) printf '%s' "$DRY_RUN_PLAN"; exit 0 ;;
esac
case "$1" in
eval) echo fixture ;;
path-info) test "$CACHE_HIT" = 1 ;;
build) test "$CHECK_PASS" = 1 ;;
shell) while [ "$1" != -c ]; do shift; done; shift; exec "$@" ;;
*) exit 0 ;;
esac
"""

STUB_GIT = """#!{bash}
case "$1" in
push) echo "git push" >> "$CALLS"; test "$PUSH_OK" = 1; exit ;;
fetch) echo "git fetch" >> "$CALLS"; exit 0 ;;
ls-remote) printf '%s\\trefs/heads/master\\n' "$REMOTE_HEAD"; exit 0 ;;
esac
exec {git} "$@"
"""

# The push routine waits between attempts.
STUB_SLEEP = """#!{bash}
echo "sleep $*" >> "$CALLS"
"""

ORIGIN = "https://example.invalid/repo.git"
REV = "a" * 40


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
    for name, stub in (("nix", STUB_NIX), ("git", STUB_GIT), ("sleep", STUB_SLEEP)):
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
        FLAKE_CHANGES="1",
        UPDATE_STATUS="0",
        DRY_RUN_PLAN="",
        PUSH_OK="1",
        REMOTE_HEAD=REV,
        T3CODE_FORK_REV=REV,
    )
    repo = root / "repo"
    repo.mkdir()
    shutil.copytree(scripts, repo / "ci")
    (repo / "flake.nix").write_text(f'{{ t3code-fork.url = "github:whexy/t3code/{"0" * 40}"; }}\n')
    setup = (
        "git init -q && git config core.hooksPath /dev/null"
        " && git config user.name fixture && git config user.email fixture@example.invalid"
        f" && git remote add origin {ORIGIN}"
        " && echo before > flake.lock && git add . && git commit -qm initial"
        " && git update-ref refs/remotes/origin/master HEAD"
    )
    assert run(setup, repo, env).returncode == 0
    return root, repo, env


def lane(commands, **overrides):
    """Run a step's commands in a fresh fixture; return its result and calls."""
    with tempfile.TemporaryDirectory() as directory:
        root, repo, env = fixture(directory)
        env.update(overrides)
        result = run("\n".join(commands), repo, env)
        calls = (root / "calls").read_text().splitlines() if (root / "calls").exists() else []
        message = run("git log -1 --format=%B", repo, env).stdout
        origin = run("git remote get-url origin", repo, env).stdout.strip()
    assert origin == ORIGIN, origin  # the App's token left the git config
    return result, calls, message


def index(calls, prefix):
    return next(i for i, call in enumerate(calls) if call.startswith(prefix))


for name, commands in lanes.items():
    # Each failing package is reverted by the driver; the lane still pushes
    # what did update, then fails so report-failure runs.
    for flake_changes, status in (("1", "0"), ("1", "1"), ("0", "0"), ("0", "1")):
        result, calls, message = lane(commands, FLAKE_CHANGES=flake_changes, UPDATE_STATUS=status)
        assert (result.returncode == 0) == (status == "0"), (name, result.stderr)
        assert ("git push" in calls) == (flake_changes == "1"), (name, calls)
        if flake_changes == "1":
            assert index(calls, "nix path-info") < index(calls, "git push"), calls
            assert "[skip ci]" not in message.lower() and "[ci skip]" not in message.lower()
            assert "package report" in message, message

    # A failed check pushes nothing; a failed push is retried 3 times.
    result, calls, _ = lane(commands, CACHE_HIT="0", CHECK_PASS="0")
    assert result.returncode != 0 and "git push" not in calls, calls
    result, calls, _ = lane(commands, PUSH_OK="0")
    assert result.returncode != 0 and calls.count("git push") == 4, calls
    assert "git fetch" not in calls, calls

    with tempfile.TemporaryDirectory() as directory:
        root, repo, env = fixture(directory)
        for hit, passes, expected in (("1", "0", 0), ("0", "1", 0), ("0", "0", 1)):
            (root / "calls").write_text("")
            result = run(check, repo, dict(env, CACHE_HIT=hit, CHECK_PASS=passes))
            assert (result.returncode == 0) == (expected == 0), result.stderr
            calls = (root / "calls").read_text()
            assert ("nix build " in calls) == (hit == "0"), calls
    print(f"{name}: failed updates still pushed, cached success reused, failed checks rejected")

# The pin lane names the stage of every failure, and pushes only a checked
# pin, rebased onto master, of a rev that is still the fork's head.
result, calls, message = lane(pin)
assert result.returncode == 0 and "OK - pinned" in result.stdout, result.stdout + result.stderr
assert message.startswith(f"chore(t3code-fork): pin {REV} (fixture)"), message
assert index(calls, "nix path-info") < index(calls, "git fetch") < index(calls, "git push"), calls
for overrides, outcome in (
    ({"T3CODE_FORK_REV": "abc"}, "FAILED(validate)"),
    ({"REMOTE_HEAD": "b" * 40}, "SUPERSEDED"),
    ({"DRY_RUN_PLAN": "these 2 derivations will be built:"}, "FAILED(cache)"),
    ({"T3CODE_FORK_REV": "0" * 40, "REMOTE_HEAD": "0" * 40, "FLAKE_CHANGES": "0"}, "NOOP"),
    ({"CACHE_HIT": "0"}, "FAILED(check)"),
    ({"PUSH_OK": "0"}, "FAILED(push) - 3 attempts"),
):
    result, calls, _ = lane(pin, **overrides)
    assert outcome in result.stdout, (overrides, result.stdout, result.stderr)
    assert (result.returncode == 0) == (not outcome.startswith("FAILED")), overrides
    assert calls.count("git push") == (3 if "PUSH_OK" in overrides else 0), (overrides, calls)
print("pin-t3code-fork: checked, rebased, pushed; every failure names its stage")

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
