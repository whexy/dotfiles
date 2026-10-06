# Repository

If the project is not on GitHub yet, create it private and push the current
default branch. The ruleset comes later, because it blocks direct pushes.

```sh
gh repo create whexy/<name> --private --source . --push
gh repo edit whexy/<name> \
  --enable-rebase-merge --enable-squash-merge=false --enable-merge-commit=false \
  --delete-branch-on-merge --enable-auto-merge --enable-wiki=false
```

PRs merge by rebase only. Every commit on a PR branch lands on the default
branch, and release-please reads each one, so every commit title must follow
`type(scope): description`.

Once Woodpecker has activated the repo ([ci.md](ci.md)), add the ruleset:

```sh
gh api repos/whexy/<name>/rulesets --method POST --input <this skill's directory>/templates/github/ruleset.json
```

The ruleset makes PRs the only way in. It allows rebase merges only and
requires `ci/woodpecker/pr/woodpecker` on a branch that is up to date with
the base. Woodpecker names that check after the event and the workflow file,
so keep the pipeline in one `.woodpecker.yaml`.

The strict up-to-date check is what makes the CI design sound. Every commit
on the default branch has exactly the tree its PR pipeline validated, release
PRs included, so pushes and tags never re-validate. Never relax it without
restoring validation on push and tag events.
