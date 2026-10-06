---
name: git-commit
description: Commit, tag, and pull request summary rules for Wenxuan's repositories, including the required Assisted-by trailer and the signing check. Use before git commit, git tag, or writing a pull request summary.
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

For LLM-based AI tooling used for commits, disclose with exactly one
`Assisted-by:` trailer in this exact form:

```
Assisted-by: <Tool Name>, <model ID>
```

- `<Tool Name>` is the harness's official product name, spelled and
  capitalized as its vendor does: `Claude Code`, `Codex`, `Pi`, `OpenCode`.
- `<model ID>` is the exact model identifier the harness runs, as the API
  takes it: lowercase, hyphenated, no provider prefix, no context-window
  suffix such as `[1m]`, and no marketing name (`claude-opus-5-5`, not
  `Claude Opus 5.5`).
- Nothing follows the model ID: no reasoning effort or thinking level, no
  parentheses, no extra words.

```
Assisted-by: Claude Code, claude-opus-5-5
Assisted-by: Pi, gpt-5.6-sol
```

A `Co-authored-by:` trailer does **not** satisfy this policy and shall
**never** be included in a commit message. Nor shall any other trailer a
harness suggests, such as `Claude-Session:`. Commits are authored by the
configured git user, never by an agent identity like
`Claude <noreply@anthropic.com>`.

Name the model you are actually running as, not the one you assume. Under Pi,
take the model ID from `PI_MODEL` (ignore `PI_PROVIDER` and
`PI_REASONING_LEVEL`); other harnesses do not expose those variables, so use
the model ID the harness or I gave you.

Pull request summaries and review comments are separate contributions and must
carry their own disclosure. Any adequate form of disclosure is permitted for
non-LLM tooling.

## Signing

Sign whenever a signing agent is available; commit unsigned only when it is
not.

git signs by default with an SSH key held by 1Password: through the local
1Password app on a physical machine (`golf`, `sheridan`, `ellison`), or
through an agent forwarded over SSH on a remote one (`mudd`, `neith`,
`phobos`, `zoozve`). Agents usually run headless with no agent forwarded, so
check once per session, before the first commit or tag, with the same
program and key git uses:

```bash
key=$(mktemp); git config user.signingkey > "$key"
prog=$(git config gpg.ssh.program || echo ssh-keygen)
if echo probe | "$prog" -Y sign -n git -f "$key" >/dev/null 2>&1; then
  echo sign
else
  echo no-sign
fi
rm -f "$key"
```

- `sign`: commit and tag normally; git signs.
- `no-sign`: pass `--no-gpg-sign` to every `git commit` and `--no-sign` to
  every `git tag` for the rest of the session. Do not first try a signed
  commit and fall back on failure, and do not change git config.

## Tagging

Signing tags is optional, like signing commits.

`tag.gpgsign=true` is set, so a bare `git tag <name>` opens an editor for the
tag message and blocks the session. Always pass `-m`. When the signing check
said `sign`:

```bash
git tag -s v0.1 -m "v0.1"
```

When it said `no-sign`, create an unsigned annotated tag:

```bash
git tag --no-sign -a v0.1 -m "v0.1"
```

## Before you commit

- Message title matches `type(scope): description`.
- Body is plain text.
- One `Assisted-by: <Tool Name>, <model ID>` trailer, with the official tool
  name, the exact model ID you are running as, and no reasoning effort.
- No `Co-authored-by:`, `Claude-Session:` or other harness trailers.
- The signing check ran once this session, and every commit and tag follows
  its result.
- `git tag` invocations pass `-m`, plus `-s` after `sign` or `--no-sign -a`
  after `no-sign`.
