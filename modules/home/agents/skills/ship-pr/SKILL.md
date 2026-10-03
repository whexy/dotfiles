---
name: ship-pr
description: Finish the task by committing, rebasing onto the latest default branch, opening a pull request, watching CI, and merging once it passes. Read when the user explicitly asks to ship the work, ship the PR, or ship it. Never run it unprompted, and not merely because a task is done or a PR is mentioned.
---

# Ship The Work As A Pull Request

Run this after the requested work is done, as the last step of the task.

1. Commit all your changes, following the `git-commit` skill. If you are on
   the default branch, create a topic branch first.
2. Fetch and rebase onto the up-to-date default branch (`main` or `master`)
   of the original repository: `upstream` for a fork, otherwise `origin`.
   Resolve conflicts, then re-run the checks relevant to your changes.
3. Push the branch and open a pull request against that default branch. Write
   the summary by the `git-commit` skill's rules. If the harness can link pull
   requests to the thread, link this one.
4. Watch the pull request's CI until it finishes. When every required check
   passes, rebase-merge it (`gh pr merge --rebase`). Never squash it or
   create a merge commit; if the repository does not allow rebase merges,
   stop and report instead of using another method. When a check fails, read
   its log, fix the cause, push, and keep watching. Stop and report when the
   failure is unrelated to your changes, the fix is unclear, or merging needs
   a review or permission you do not have.

Finish with the pull request URL and whether it merged.
