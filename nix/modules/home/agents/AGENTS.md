# Global Agent Rules

These rules apply to every project, regardless of language or tooling.
Project-level instruction files (AGENTS.md, CLAUDE.md, etc.) take
precedence over this file when they conflict.

## About me

My name is Wenxuan Shi, also known as Whexy.
My GitHub account is https://github.com/whexy/.

## Rules

### Environment

You are most likely running in a nix-managed system. It can be NixOS, or
nix-darwin managed macOS, or home manager managed non-NixOS Linux system.

Expect environment can be different than Ubuntu. For example, Filesystem
Hierarchy Standard are not guaranteed. glibc is not always at
`/lib/x86_64-linux-gnu/libc.so.6`.

**Blueprint**

Most of my projects have flake configured with `numtide/blueprint`.
It uses a folder structure to auto discover devshells, packages, formatters,
checks, etc. Details about blueprint folder structure can be seen here:
https://numtide.github.io/blueprint/main/getting-started/folder_structure/

**Dev Environment**

When you find a software not available in your environment:

You can use `nix run` or `nix shell` to temporarily run softwares not installed.

If the project has declared its develop environment (e.g., via devshell, devenv,
devbox, or dev-container), and you believe the software can always make
developing this project easier. You can make it permanent by adding it as a
separate commit. This includes test suites, language tools, or helpful libraries
making check, monitoring and debug easier. Only add when you actually need it
for current task, and generally believe future tasks may also need it.

### Run commands

If you want to stop or restart some process, never use `pkill`. Always `kill`
with exact PID. You must not kill process that are not launched by you, unless
specifically asked.

### VCS

For version control systems like git.

Read the `git-commit` skill before running `git commit` or `git tag`, and
before writing a pull request summary. It is the authority on message format,
signing, tagging, and the mandatory tooling disclosure trailer. Do not
reconstruct those rules from memory.

If that skill is not available in this session, ask me for the rules instead of
guessing.

### Coding

**Comments**

A comment states the non-obvious reason at the owning boundary. Include a
constraint or invalidation condition only when a maintainer needs it to know
when the rationale or code stops being valid. Do not restate the operation,
preserve intermediate attempts, or list speculative future work.

**Correct**

When correcting your own mistake, produce the result as if the mistake never
happened. Do not mention the rejected approach anywhere (e.g., comments, commit
messages, PR) unless its history is materially necessary. Do not add code or
explanation whose only purpose is to document why the rejected approach is
absent.
