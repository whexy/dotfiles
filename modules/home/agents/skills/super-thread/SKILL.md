---
name: super-thread
description: How Wenxuan wants a T3 Code super thread to coordinate its task - splitting it into member threads, one PR per piece, planning releases, briefing members, keeping the task map current, and reporting back. Use whenever your prompt carries a <super_thread_role> block, which only a super thread's prompts do; not in the member threads it starts or in ordinary threads.
---

# Coordinating a super thread

These are my preferences on top of the `<super_thread_role>` block. Where
they differ from its defaults, follow these.

## Delegate by default

Your job is to plan, launch member threads, track them on the map, steer
them, and put their results together. Do not do project work yourself.
Reading enough code and docs to plan is fine; editing, building and
committing belong to members.

## Plan first

- Read how I asked. For a big or ambiguous feature, show me the plan before
  any member builds; when I say "push until ready", execute. When it is
  unclear which I want, ask.
- Ask my fallback and rollback preferences with the plan, then hold to them.
  Never write in a fallback I have not chosen.

## Split the work

- One piece of work per member thread, and one PR per piece. A piece is
  something a member can finish and I can review on its own.
- Draw dependencies as they are: a piece that needs another's result waits
  for it on the map, and its member starts from that result.
- Start each member in its own worktree from the project's default branch,
  unless the piece builds on another piece's unmerged work.
- Pick each member's harness by its model's family: Claude Code for Claude,
  Codex for GPT, Antigravity for Gemini, OpenCode for every other model.

A project's own instructions win over "one PR per piece". The dotfiles repo,
for example, commits straight to master and opens no PRs.

## Releases and CI

- Before you steer CI or a release, list the project's scheduled and webhook
  tasks and other bots that push or start builds. Pause them or coordinate
  with them, and resume them when you are done; otherwise they act against
  the plan.
- Decide the ship points in the plan: when releases happen, and which pieces
  each carries. Batch pieces into one release, since each release can
  restart everything it deploys to.
- Keep every release and promotion with you.
- Prove risky infrastructure, such as a new CI runner, on its own before a
  release depends on it: run a job that publishes nothing first.

## Brief each member

A member knows only its brief. Give it:

- the goal of its piece and how it fits the whole task;
- the scope: what it owns, and what belongs to other pieces;
- ground rules: the project's instruction files, the `git-commit` skill,
  and anything it must not do without asking;
- what counts as done, and what to report back.

Every brief also sets these rules:

- Wait only in ways that return to you, such as an awaited command; never
  leave a PR watch nobody awaits. Keep GitHub API calls few: every member
  shares one rate limit.
- Never read another app's secrets. Ask me, or get access through the proper
  channel.
- Publish nothing to external or public services, such as gists.
- Never push to a protected or release branch, and never promote or release.

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

## Stay with the task

Follow the task until all of it is done. When I ask you something mid-task,
answer, then pick the members back up in the same turn: check on each and act
on what changed, rather than ending the turn at your answer.

End a turn with work in flight only when something will wake you, such as a
member's outcome waking the super thread. Never go idle with work in flight
and nothing to wake you; keep waiting on the members instead.

## When a member stops

A member that stops on a design problem hands the decision back to you.
Decide whether the plan changes, update the map, and steer the member or
launch a new one. If the decision is mine to make, ask me rather than guess.

Hold a member's ask for me to the same rule. Before you pass it on, check
whether a member could do it instead; if so, send it back with that
instruction.

Launch a fix member only with evidence of the bug: a reproduction, or logs
that show it. A failure seen once in one member's test is not enough.

## When a member finishes

- Check a member's numbers and security claims before you pass them to me,
  or mark them unverified. Have members prove a security property by testing
  it, not by reading code.
- Settle a member once its work is merged and verified. Send a later fix in
  its area back to that member rather than starting a new one.

## Talk to me

- Decide what is reversible or low-stakes yourself. Ask me only what is mine,
  all my open decisions in one message, and do not repeat an open question
  in every update.
- When I say "make it work, don't bother me", act with my full authority;
  stop only for something destructive or a secret.
- On a wake that brings nothing new, reply in one line or not at all. Do not
  resend the status.
- Keep separate facts separate. Present two facts as cause and effect only
  when one caused the other.

## Report back

When the task is done, or cannot go further without me, report:

- each piece's PR link (or commit, where the project takes no PRs);
- every piece a member stopped on, and why;
- anything waiting on my decision.
