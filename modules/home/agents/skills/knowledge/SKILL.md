---
name: knowledge
description: Wenxuan's cross-machine knowledge base (~/.knowledge) of verified findings about codebases and systems. Use before studying how an unfamiliar repo or system works, and after an investigation produced findings worth saving. Not for debugging the current repo.
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
  then update the entry (see [writing.md](writing.md)).
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

## Writing

When a finding passes the checks above, read [writing.md](writing.md) for the
entry format and how to save it.
