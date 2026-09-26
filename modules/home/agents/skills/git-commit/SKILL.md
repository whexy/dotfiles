---
name: git-commit
description: Rules for recording work in git in Wenxuan's repositories - commit message format, signing behaviour, the mandatory Assisted-by tooling disclosure trailer, and how to tag without hanging the session. Read before running git commit, git tag, or writing a pull request summary.
---

# Committing In My Repositories

Follow every rule below. They apply to all of my repositories unless a
project-level instruction file contradicts them.

## Commit messages

Title must follow `type(scope): description`. Common types are feat, fix,
docs, style, refactor, test, and chore.

```
feat(auth): implement JWT token refresh strategy
```

The message body is plain text, no markdown. Bullet lists are allowed.

## Disclosure

All covered use of automated tooling for a contribution must be disclosed as
part of that contribution.

For LLM-based AI tooling used for commits, disclose with an `Assisted-by:`
trailer naming at least the tool and the primary model name and version:

```
Assisted-by: Codex, gpt-5.6 sol medium
```

A `Co-authored-by:` trailer does **not** satisfy this policy and shall
**never** be included in a commit message.

Name the model you are actually running as, not the one you assume. Under pi,
read `PI_PROVIDER`, `PI_MODEL`, and `PI_REASONING_LEVEL` from the environment;
other harnesses do not expose those variables, so use the identity the harness
or I gave you.

Pull request summaries and review comments are separate contributions and must
carry their own disclosure. Any adequate form of disclosure is permitted for
non-LLM tooling.

## Signing

Signing commits is optional.

git is configured to sign by default. The signing key comes from a local
1Password agent on a physical machine (`golf`, `sheridan`, `ellison`), or from
a forwarded agent over SSH on a remote one (`mudd`, `neith`, `phobos`,
`zoozve`). When that agent is unavailable, for example because SSH forwarding
is down, commit without signing rather than waiting on it.

## Tagging

Signing tags is optional, like signing commits.

`tag.gpgsign=true` is set, so a bare `git tag <name>` opens an editor for the
tag message and blocks the session. Always pass `-m`. Sign when the agent is
available:

```bash
git tag -s v0.1 -m "v0.1"
```

Without an agent, `git tag -s` fails immediately with `Couldn't get agent
socket?`. Create an unsigned annotated tag instead:

```bash
git tag --no-sign -a v0.1 -m "v0.1"
```

## Before you commit

- Message title matches `type(scope): description`.
- Body is plain text.
- An `Assisted-by:` trailer names the tool and the model you are running as.
- No `Co-authored-by:` trailer.
- `git tag` invocations pass `-m`, plus `-s` with an agent or `--no-sign -a`
  without one.
