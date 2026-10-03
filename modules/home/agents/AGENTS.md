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

### Skills

My skills hold rules you cannot reconstruct from memory. Read the matching
skill before the task, every time; if it is not available in this session, ask
me instead of guessing.

- `git-commit`: before `git commit`, `git tag`, or writing a pull request
  summary.
- `knowledge`: before learning how an unfamiliar codebase or system works,
  especially one outside the current repository (a service you deploy to, a
  host you write a plugin for), and after an investigation that produced
  durable findings about how it works. Not for diagnosing, debugging, or
  fixing a bug in the current repository.
- `nix-blueprint`: before adding, moving, or wiring a file in a flake built
  with `numtide/blueprint`, which most of my projects use.
- `design`: before designing or implementing UI, or writing or reviewing
  documentation.
- `web-preview`: before starting a server or preview, checking a UI,
  taking a screenshot, or giving me a URL.
- `explain`: when I ask for an explanation or help understanding something;
  confirm the output format first. Not for explanations that come with
  implementation, fixes, reviews, or status updates.
- `deploy-to-cluster`: before deploying a project to the cluster or changing
  its repository settings, CI, release flow, image, or cluster manifests.
- `ship-pr`: when I ask you to ship the work, ship the PR, or ship it. Do the
  rest of the task first. Never ship unasked.

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
