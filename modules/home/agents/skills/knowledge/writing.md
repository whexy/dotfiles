# Writing to the knowledge base

Check "Whether to store" and "Layout" in SKILL.md first.

## Entry format

Every file starts with this frontmatter:

```yaml
---
repo: github.com/whexy/t3code
upstream: github.com/pingdotgg/t3code # forks only
branch: self-hosted
commit: 0123456789abcdef0123456789abcdef01234567
paths:
  - apps/mcp/
  - apps/server/src/provider/
studied_at: 2026-10-03T15:20:00Z
author: Claude Code, claude-opus-5-5
answers:
  - How does the MCP bridge discover models and reasoning efforts?
---
```

- `commit`: the full 40-character SHA that **every** claim in the file was
  verified against. If you verified only some sections, verify the rest or
  move your part to its own file. Never bump the commit for claims you did not
  check.
- `paths`: the files or directories the claims depend on, as narrow as is
  honest. Freshness checks rely on this list; a path you leave out is a
  change nobody will notice.
- `studied_at`: UTC, ISO 8601, when the verification finished.
- `author`: the harness and exact model ID, in the same form as the
  `Assisted-by` trailer of the git-commit skill.
- `answers`: the questions this file answers, phrased the way someone would
  ask them. Readers grep for these.

Entries under `topics/` replace `repo`, `branch`, `commit`, and `paths` with:

```yaml
sources:
  - https://woodpecker-ci.org/docs/usage/workflow-syntax
verified_at: 2026-10-03T15:20:00Z
verified_by: "Pipelines for a pre-release in whexy/hey-chat never started"
```

The body:

- Lead with the answer, then the detail that supports it.
- Anchor every claim to code: `path/to/file.ts:123` or a symbol name, so a
  reader can jump there and re-check it.
- State what the code does, not how you found out. No narrative of the
  investigation, no rejected hypotheses unless a reader would otherwise
  repeat the mistake; then say it in one line as a gotcha.
- When updating, rewrite stale claims in place and refresh the frontmatter.
  Do not append a changelog; git history keeps it.

## Saving

After writing, scan your diff for secrets, then commit and push:

```sh
cd ~/.knowledge
git add -A
git diff --cached
git commit -m "docs(<repo-or-topic>): <what was learned>"
git pull --rebase --quiet && git push --quiet
```

Follow the git-commit skill for the message and trailer. If the push is
rejected, pull with rebase and push again; resolve a conflict by merging both
sides' facts, never by dropping the other side.

Tell the user in one line which entries you added or updated.
