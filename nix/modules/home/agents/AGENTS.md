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

**Signing**

Signing commits are optional.

Tools like `git` are configured to sign commits by default. The signing key are
provided by either a local 1Password agent (on a physical machine, like `golf`,
`sheridan`, and `ellison`), or a forwarded agent through SSH (on a remote
machine, like `mudd`, `phobos`, and `zoozve`).

If signing agent is currently unavailable (e.g., SSH forwarding is not working),
commit without signing.

**Commit Messages**

Title must follow format: `type(scope): description`.
Common types includes feat, fix, docs, style, refactor, test, and chore.
Example: `feat(auth): implement JWT token refresh strategy`

Commit message must be plain text, no markdown. Bullet list is allowed.

**Disclosure**

All covered use of automated tooling for a contribution must be disclosed as
part of that contribution.

In the case of LLM‐based AI tooling used for commits, this must be in the form
of an `Assisted-by:` commit trailer, including at least the tool name and the
primary model name and version used for the contribution.
A `Co-authored-by:` trailer does **not** satisfy this policy and shall **never**
be included in commit messages.
Example: `Assisted-by: Codex, gpt-5.6 sol medium`

Any adequate form of disclosure is permitted for other kinds of tooling and
contribution. Pull request summaries and review comments must be disclosed
separately to commits.

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
