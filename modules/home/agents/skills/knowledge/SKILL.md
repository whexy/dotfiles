---
name: knowledge
description: Wenxuan's private, cross-machine knowledge base of what earlier agents learned about codebases and systems, at ~/.knowledge. Read before studying, investigating, or answering "how does X work" about any codebase or system (including one other than the current repo, e.g. a service you deploy to or write a plugin for). Read again after an investigation that produced durable findings, to save them for future agents.
---

# Knowledge Base

`~/.knowledge` is a clone of the private repo `github.com/whexy/knowledge`,
shared by every agent on every one of Wenxuan's machines through GitHub. It holds verified
findings about codebases and systems so that no agent has to investigate the
same thing twice.

The knowledge base is private, but this skill is public. Never quote its
contents anywhere public (public repos, issues, PRs, commit messages of
public repos).

## Bootstrap

If `~/.knowledge` does not exist on this machine, clone it:

```sh
gh repo clone whexy/knowledge ~/.knowledge
```

If that fails because `gh` is not logged in, ask Wenxuan to run
`gh auth login`, and carry on without the knowledge base meanwhile.

## Reading

Always pull first; another machine may have written since:

```sh
git -C ~/.knowledge pull --rebase --quiet
```

If the pull fails, say so in one line and use the entries as they are.

Find entries by the target's repo key (see Layout), then search the whole tree,
because facts about one project are often recorded under another (for example,
how an app is deployed lives under the cluster repo):

```sh
ls ~/.knowledge/github.com/<owner>/<repo>/
grep -ril '<project or symbol>' ~/.knowledge --include='*.md'
```

Start from the repo's `overview.md` when it exists.

### Check freshness before trusting an entry

Every entry records the commit it was verified against and the `paths` its
claims depend on. In a local checkout of that repo:

```sh
git fetch --quiet
git log --oneline <commit>..<branch-or-HEAD> -- <paths...>
```

- No output: nothing the entry depends on has changed. Use it as is.
- Commits listed: re-verify only the claims those commits could affect,
  then update the entry (see Writing).
- `<commit>` unknown locally (shallow or stale clone): fetch it, or compare
  remotely with `gh api repos/<owner>/<repo>/compare/<commit>...<branch>`.

An entry is a strong lead, not ground truth. If the code you are reading
contradicts it, the code wins; fix the entry.

## Whether to store

Store a finding only when all of these hold:

1. It cost real investigation: tracing code, reading many files, running
   experiments, or learning it from a failure.
2. A future agent is likely to need it again.
3. It is not already stated in that project's own README, docs, or AGENTS.md.
4. You verified it against the code or by running something. Do not store
   guesses, plans, or what a document claims without checking.

Never store:

- Secret values: tokens, keys, passwords, cookies, private URLs with embedded
  credentials. Recording _where_ a secret lives (an agenix file, a Kubernetes
  Secret name and key) is fine.
- Task progress, one-off debugging state, or anything only this session needs.
- Wenxuan's preferences or rules for how agents should work. Those belong in
  his global agent rules or a skill, not here.

When in doubt, store less. An unhelpful entry costs every future reader time.

## Layout

```
~/.knowledge/
  github.com/<owner>/<repo>/
    overview.md          # what the repo is, architecture map, index of topics
    <topic>.md           # one question area per file, kebab-case
  topics/<name>/
    <topic>.md           # knowledge not owned by one repo (a CI service's quirks)
```

- The repo key comes from the origin remote: host, owner, and repo, lowercase,
  with no scheme, user, or `.git` (`git@github.com:whexy/T3Code.git` becomes
  `github.com/whexy/t3code`).
- Knowledge about a fork lives under the fork, with `upstream` set. Knowledge
  that holds for upstream too goes under the upstream repo.
- Knowledge about a deployed system lives under the repo that defines it (the
  cluster repo for cluster operations, dotfiles for hosts).
- Use `topics/` only when no repo owns the knowledge.
- One topic per file, at most about 300 lines. Split a file that grows past
  that. Keep `overview.md` listing every topic file with one line each.

## Writing an entry

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

Follow the git-commit skill for the message and trailer. Signing is optional
here. If the push is rejected, pull with rebase and push again; resolve a
conflict by merging both sides' facts, never by dropping the other side.

Tell the user in one line which entries you added or updated.
