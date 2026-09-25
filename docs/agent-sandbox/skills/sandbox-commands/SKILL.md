---
name: sandbox-commands
description: Run commands in the code sandbox without losing output or getting cut off. Use for any command that may print a lot, run longer than a couple of minutes, or keep running in the background (builds, test suites, dev servers, installs).
---

# Running commands in the sandbox

Each sandbox command starts a fresh `/bin/sh`. Nothing carries over between
calls except files and background processes: `cd`, `export` and shell
functions all reset. Chain steps with `&&` inside one command.

## Limits you are working against

| Limit                                                         | Consequence                                              |
| ------------------------------------------------------------- | -------------------------------------------------------- |
| Command timeout (5 minutes unless the call sets a longer one) | The whole process group is killed                        |
| About 16 MB of output kept per command                        | Older output is dropped                                  |
| A single output line longer than about 64 KB                  | The output stream may stall until the timeout            |
| Inactivity stop after about an hour with no requests          | Every process dies, background jobs included. Files stay |
| Command text is logged by the sandbox service                 | Never put secrets in commands                            |

If a call returns a "sandbox restarted" error (HTTP 409), the sandbox came
back without its processes. Files are intact, so restart any background jobs
and retry.

## Keep output small

Send output to a file, then read only what you need:

```sh
cd ~/projects/app && npm test > /tmp/test.log 2>&1; echo "exit=$?"
tail -n 40 /tmp/test.log
rg -n -m 20 -e 'FAIL|Error|error:' /tmp/test.log
wc -l /tmp/test.log
```

- Structured output: filter with `jq` (`jq '.items | length'`,
  `jq -c '.[] | {name, status}' | head`).
- Long or minified lines: `cut -c1-300`, or `jq`/`fold` for JSON.
- Unknown files: run `file <path>` and `head -c 2000` before printing a whole
  file. Never print binaries or lockfiles in full.
- Listings: `tree -L 2 -I node_modules`, or `fd -t f | head -100`, not a
  recursive `ls` of the whole repo.
- Quiet flags for noisy tools: `npm ci --no-audit --no-fund --loglevel=error`,
  `pip install -q`, `git clone -q`, `make -s`.

## Long-running jobs: start, then poll

Anything that may exceed a couple of minutes runs in the background, with
its exit code saved:

```sh
cd ~/projects/app && nohup sh -c 'make build; echo $? > /tmp/build.rc' > /tmp/build.log 2>&1 &
echo $! > /tmp/build.pid
```

Poll in short, bounded steps (each call finishes well under the timeout):

```sh
for i in $(seq 12); do [ -f /tmp/build.rc ] && break; sleep 10; done
if [ -f /tmp/build.rc ]; then echo "done exit=$(cat /tmp/build.rc)"; else echo running; fi
tail -n 20 /tmp/build.log
```

- Each poll also counts as activity, which keeps the sandbox from stopping.
- Do not wait with one long blocking command (`sleep 900`, `tail -f`,
  `wait`).
- To cancel: `kill "$(cat /tmp/build.pid)"`.

## Servers and watchers

Start them in the background, wait for readiness with a bounded loop, and
stop them when done:

```sh
cd ~/projects/app && nohup npm run dev -- --port 3000 > /tmp/dev.log 2>&1 & echo $! > /tmp/dev.pid
for i in $(seq 30); do curl -fsS -o /dev/null http://127.0.0.1:3000 && echo ready && break; sleep 2; done
```

Test against `127.0.0.1` from inside the sandbox; nothing outside can reach
the port. Stop with `kill "$(cat /tmp/dev.pid)"`. Turn watch modes off
(`CI=1` is already set, which most test runners respect).

## Report honestly

State the exit code and the relevant log lines for every build or test you
cite. If a job was cut off by a timeout or restart, say so rather than
reporting it as passed.
