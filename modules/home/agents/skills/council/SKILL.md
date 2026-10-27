---
name: council
description: Bring in three delegates, one strong model from each of three providers, to review or give feedback on the user's request, and summarize their findings. Use when the user says "council".
---

# Council

Bring in three delegates to help with the user's request, usually for review
or feedback. Use one strong model from each of three different providers, at
high reasoning effort. If the user's instructions name council members, use
those. Otherwise the council is the latest flagship of each family, run
through that provider's own harness:

- Claude Opus, through Claude Code
- GPT Sol, through Codex
- Muse Wonder Full, through OpenCode

Codex and OpenCode also list other vendors' models. Take each member from its
family's harness, including members the user names: Claude Code for Claude,
Codex for GPT, OpenCode for every other model.

In T3 Code, use `orchestrator_capabilities` to resolve each member to its
provider instance and current model ID (pass `search` when one is not listed),
then `delegate_task` to start one delegate per model in parallel. Set high
effort in `target.options` through each model's own option descriptor.
Elsewhere, use the harness's subagent tools. If you cannot reach three
providers, or a member is unavailable, report it instead of substituting.

Give each delegate the request and relevant context. For review or feedback,
keep their work read-only. Collect their responses and summarize the useful
findings, disagreements, and recommended next steps.

For a code review, ask each delegate for a score out of 10.
Count each full review pass as one round.
A fresh review after fixes starts a new round.

If the work ends in a pull request, put the results in the PR description.
Put this section above the model disclosure at the end:

```markdown
## Council review

Rounds: 2

| Delegate         | Round 1 | Round 2 |
| ---------------- | ------- | ------- |
| Claude Opus      | 7/10    | 9/10    |
| GPT Sol          | 8/10    | 10/10   |
| Muse Wonder Full | 7/10    | 9/10    |
```

If a delegate gives no score, write `no score`. Do not invent one.
If the PR is open, edit the description. Do not post a comment for this.
If there is no PR, put the same results in the final reply only.

If you agree with their recommendations, make the changes and request a fresh
review after. Continue this process until all delegates are satisfied with the
outcome.

Do not let repeated reviews result in scope creep. It is your job to fight to
keep scope limited.
