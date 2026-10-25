---
name: review-loop
description: Review a change in rounds with one independent reviewer from a different model provider than the author, until both agree. Use when the user asks for a review loop, an independent or cross-provider review, or to cross-check a change before shipping it.
---

# Review Loop

An agent reviewing its own work shares its blind spots. This skill gets one
reviewer from a different model provider or family than the model that wrote
the change, then loops: review, fix or push back with evidence, re-review,
until the reviewer approves the current diff or the budget runs out.

Make the smallest changes that answer real findings. Review rounds grow a diff
one cheap-looking fix at a time; holding the scope is your job, not the
reviewer's.

## Budget

- Default: 3 rounds. Round 1 reviews the full change; later rounds check only
  changed code and open findings.
- Extend to 5 only for security, permissions, auth, data loss, or
  state/concurrency changes while a `blocker` or `should` stays open with
  evidence, or when the user asks.
- Stop early when a round returns only nits. Declined nits and comment, doc, or
  format-only fixes need no new round.
- One reviewer only. The reviewer must not start subagents or reviewers of its
  own.
- Keep a ledger per finding: id, severity, outcome. Record token usage only if
  the harness reports it; never guess it.

## 1. Scope

Run `git status --short`. Do not stash, discard, or include unrelated changes.
Limit the review to the change's paths if they separate cleanly; otherwise stop
and ask.

Find the base after `git fetch origin`:

- For a PR: `gh pr view <n> --json baseRefName,headRefOid`. Check out the
  branch only if the worktree is clean. Confirm `HEAD` is the PR head, or ahead
  of it only by this change. Base: `git merge-base HEAD origin/<baseRefName>`.
- Local change: `git merge-base HEAD origin/<default-branch>`. With no remote,
  use a base the user names, or `HEAD` for uncommitted changes only.

The change is that base to the working tree in the scoped paths, including
untracked files. Use one diff command for every round. State the intent and
what is out of scope in 1–2 sentences. Run the checks that cover the change
first; do not send code you know is broken. Note missing or already-failing
checks in the brief.

## 2. Pick and start the reviewer

The reviewer is one strong model from a provider or model family different
from the authoring model's — the latest flagship of another provider, at high
reasoning effort where the harness lets you set it. If the user names a model
or provider, use that. Do not hardcode a model ID in this skill or the brief.

In T3 Code, call `orchestrator_capabilities` to resolve the model, then start
every round with a fresh `delegate_task` (`role: "review"`, `mode: "async"`).
Save the `taskId`. Use a new `clientRequestId` per round. The `childThreadId`
is storage, not the next round's target; do not use `t3_thread_send`,
`create_threads`, or `t3_thread_launch` for review rounds. If T3 tools are not
listed, make one direct capability call before concluding they are absent.

Outside T3 Code, use the harness's subagent tool only if it can actually run
the chosen model (a model parameter, or a custom subagent already configured
for it), and keep the returned agent ID. If no route runs a model from another
provider, report that blocker; do not substitute a same-provider model and call
it independent review.

Do not edit the scoped files while a round runs. Wait for its result; do not
poll or start a second reviewer. A timeout, error, or missing reply is not
approval: cancel the round, confirm it stopped, and restart it with the
ledger.

Round 1 brief (delegated children get no conversation history):

```text
Review only. Do not edit, commit, push, comment on PRs, or start subagents.
Repo: <abs path> Base: <sha> Intent: <intent> Out of scope: <scope> Checks: <results>
See: git diff <base> [-- <paths>]; git status --short (read untracked files too).
Read the surrounding code. Find bugs, broken callers, and mismatches with the intent.
Skip style unless it hides a bug. Hold to the smallest change that meets the intent;
flag code, tests, or guards the intent does not need. Other paths, rare cases, small
performance costs, and extra compatibility are nits.
blocker = the intended case is wrong. should = a real bug callers will hit, within
the intent. nit = everything else.
Reply:
VERDICT: APPROVE or CHANGES
F1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion> (use stable ids)
```

## 3. Answer the findings

Verify every finding and its severity yourself against the code. A finding
about another path, a rare case, or a small cost is a nit whatever label it
arrived with.

- Agree: make the smallest fix. Prefer deleting or narrowing code over adding a
  lock, cache, helper, or option. Fix the case that happened. Add one focused
  test that fails without the fix when the intent needs one.
- Disagree: say why, with evidence (file and line, a test, command output).
- Out of scope or nit: decline in one line and list it as a follow-up.

Update the ledger. Re-run the covering checks and
`git diff --shortstat <base>`; if answering the review grew the diff, cut
before the next round. Do not agree just to end the loop.

## 4. Next round

Start one only when budget remains and a `blocker` or `should` is open,
behavior code changed, or the last approval does not cover the current diff. In
T3 Code use a fresh `delegate_task`; outside it, follow up with the saved
native agent ID. Send the round 1 brief, the ledger (`fixed:` / `disagree:` /
`declined:` with evidence), the same base diff, and what changed since the last
round. Tell the reviewer to cover open ids and changed code only, marking each
old id `resolved` or `still open: <reason>`.

## 5. Stop and report

- **Agreed:** `APPROVE` on the current behavior diff, no `blocker` or `should`
  open, and no concern of your own.
- **Stuck:** a finding stays disputed after two replies, or the budget ends.
  Show both sides in 2–3 lines each and let the user decide. Running out of
  budget is not approval.

Do not push during the loop. Push after agreement only if the user asked to
push, ship, or update a PR. If the change goes into a PR description, add one
line above the model disclosure:

```text
Reviewed with review-loop: <N> rounds with <reviewer model>. Verdict: approved.
```

Name the model as the harness reports it; add reasoning effort or usage only
when verified. With no PR, the same results go in the final reply only.

Report: rounds run, reviewer model, what the review changed, diff size before
and after, fixed and declined findings with reasons, usage if the harness
exposed it (otherwise say so), and whether you pushed.
