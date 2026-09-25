# Sandbox environment

You are working inside a disposable Linux sandbox. Your only way to act on it
is to send one shell command at a time, and to read and write files. This card
covers what you cannot easily discover by running commands.

## Shell

- Every command runs in a **fresh `/bin/sh`** (bash in POSIX mode). The
  working directory, `export`ed variables, aliases and shell functions do
  **not** carry over to the next command. Chain steps in one command
  (`cd ~/projects/app && make test`) or pass a working directory.
- No terminal is attached. Anything that prompts or opens an editor fails or
  waits forever. Always pass non-interactive flags (`-y`, `--yes`,
  `git commit -m …`).
- These defaults are set unless the caller overrides them: `LANG=C.UTF-8`,
  `TZ=UTC`, `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `EDITOR=true`,
  `GIT_EDITOR=true`, `CI=1`, `NO_COLOR=1`, `NIX_PATH=nixpkgs=flake:nixpkgs`.

## You are not root

- You run as `user` (uid 1000) with no capabilities. `sudo`, `apt`, Docker
  and Podman are unavailable. Do not try to work around this.
- You can write only to `/home/user`, `/tmp` and the Nix store.

## Layout

| Path                | Use                                                            |
| ------------------- | -------------------------------------------------------------- |
| `~/projects/<name>` | Put repositories and your own work here                        |
| `~/workspace`       | Reserved for n8n workflow builds. Do not use it for other work |
| `~/venv`            | Python virtualenv, already first on `PATH`                     |
| `~/.npm-global`     | Prefix for `npm install -g`, already on `PATH`                 |
| `/tmp`              | Scratch space                                                  |

## Getting tools

Preinstalled:

- git, git-lfs, gh (not logged in)
- rg, fd, ast-grep, sd, jq, yq, tree, file, patch, diff
- curl, wget, rsync, rclone, zip/unzip, 7z, zstd
- gcc, make, cmake, pkg-config, just
- python3, uv, node, npm, pnpm, tsc, sqlite3
- strace, ltrace, lsof, gdb, dig

Missing something? In order of preference:

1. **Nix.** `nix shell nixpkgs#<pkg> -c <cmd> …` or `nix run nixpkgs#<pkg> -- …`.
   `nixpkgs` is pinned to the revision this sandbox was built from, so most
   packages are already local. To find which package provides a command, run
   `nix-locate --minimal --whole-name --at-root /bin/<cmd>`.
2. **Language package managers**, per project: `pip install` (goes into
   `~/venv`), `uv`, `npm`/`pnpm`, `npm install -g`.

Nix builds run without the Nix sandbox. `nix run` of an arbitrary flake is
arbitrary code execution, so only run flakes you trust, and never pass
`--accept-flake-config`.

## Network

The network may be off entirely, or open to the public internet with all
private networks blocked. If a download fails, try once more. If it fails
again, report it rather than retrying in a loop.

## Git

- Commits are authored as `Sandbox Agent <agent@sandbox.invalid>` and are not
  signed.
- There are **no credentials** here: you can clone public repositories, but
  pushing and pull requests happen through tools outside the sandbox.
  Hand back your change as `git diff` or `git format-patch` output.

## Shared space

Files that must outlive this sandbox, or that other agents or people need,
go to the shared space: an object-storage bucket every agent can reach as the
rclone remote `shared:`. It needs a one-time setup per sandbox. See the
`shared-space` skill.

## Output and long commands

- Keep command output small. Redirect big output to a file and read it
  selectively (`cmd > /tmp/out.log 2>&1; tail -n 50 /tmp/out.log`,
  `rg -n error /tmp/out.log`).
- Avoid single output lines longer than a few thousand characters (minified
  files, JSON blobs): pipe through `jq`, `cut -c1-500` or `fold`.
- Run anything that may take more than a few minutes in the background and
  poll it:
  `nohup make build > /tmp/build.log 2>&1 & echo $! > /tmp/build.pid`, then
  `tail -n 20 /tmp/build.log; kill -0 "$(cat /tmp/build.pid)" && echo running`.

## Lifecycle

- After a period of inactivity the sandbox is stopped. Stopping kills all
  processes, including background jobs and servers. Files survive until the
  sandbox is deleted.
- The sandbox is deleted after the task. Never treat it as storage. Anything
  worth keeping must leave as a diff or a patch, or go to the shared space.
