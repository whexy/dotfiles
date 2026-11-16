---
name: super-thread
description: How Wenxuan wants a T3 Code super thread to coordinate its task - splitting it into member threads, one PR per piece, briefing members, keeping the task map current, and reporting back. Use whenever your prompt carries a <super_thread_role> block, which only a super thread's prompts do; not in the member threads it starts or in ordinary threads.
---

# Coordinating a super thread

These are my preferences on top of the `<super_thread_role>` block. Where
they differ from its defaults, follow these.

## Delegate by default

Your job is to plan, launch member threads, track them on the map, steer
them, and put their results together. Do not do project work yourself.
Reading enough code and docs to plan is fine; editing, building and
committing belong to members.

## Split the work

- One piece of work per member thread, and one PR per piece. A piece is
  something a member can finish and I can review on its own.
- Draw dependencies as they are: a piece that needs another's result waits
  for it on the map, and its member starts from that result.
- Start each member in its own worktree from the project's default branch,
  unless the piece builds on another piece's unmerged work.
- Pick each member's harness by its model's family: Claude Code for Claude,
  Codex for GPT, OpenCode for every other model.

A project's own instructions win over "one PR per piece". The dotfiles repo,
for example, commits straight to master and opens no PRs.

## Brief each member

A member knows only its brief. Give it:

- the goal of its piece and how it fits the whole task;
- the scope: what it owns, and what belongs to other pieces;
- ground rules: the project's instruction files, the `git-commit` skill,
  and anything it must not do without asking;
- what counts as done, and what to report back.

Tell each member: if something in the design turns out wrong or impossible,
stop that piece and report back with what you found. Do not redesign it.
A member also stops and reports before anything destructive or outside its
repository.

Also tell it: do not hand me work an agent can do. When a step needs someone
to act in an app or system, the member does it as me with the tools it has,
such as by driving the app; that is the default, not a fallback. It asks me
only for what nobody else can supply: a secret or login, a decision that is
mine, or approval before something destructive or outside its repository.

## Keep the map current

I follow the task on the map, not in your transcript.

- Draw the map once you know the plan.
- Link each thread you launch to its node.
- Update the map on every plan change: a new piece, a dropped one, a
  blocker, a member's report that changes what comes next.

## When a member stops

A member that stops on a design problem hands the decision back to you.
Decide whether the plan changes, update the map, and steer the member or
launch a new one. If the decision is mine to make, ask me rather than guess.

Hold a member's ask for me to the same rule. Before you pass it on, check
whether a member could do it instead; if so, send it back with that
instruction.

## Report back

When the task is done, or cannot go further without me, report:

- each piece's PR link (or commit, where the project takes no PRs);
- every piece a member stopped on, and why;
- anything waiting on my decision.
