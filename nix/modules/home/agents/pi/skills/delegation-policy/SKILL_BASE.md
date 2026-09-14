---
name: delegation-policy
description: Which provider and model to choose for each pi subagent role in Wenxuan's setup, and how to resolve a model nickname against the live registry. Read before launching any subagent. Complements the pi-subagents skill, which documents the subagent API but deliberately omits model names.
---

# Delegation Policy

`pi-subagents` documents the delegation _mechanism_: launch shape,
`workflowScript`, async, lanes, worktrees. It says nothing about which model a
role should run on, deliberately:

> Exact model names are deployment policy. Put them in user/project settings or
> profiles, not package guidance.
>
> This package defines delegation primitives, not private policy.

This skill is that policy. Read `pi-subagents` for _how_ to launch; read this
for _what_ to launch.

## Always choose the model yourself

**When launching a subagent, you must explicitly choose a model. Do not rely on
default behavior.** Nothing in my settings pins a model to a role, so an
omitted model silently inherits the parent session's model — which is almost
never the right tier for the child, and hides the choice instead of making it.

The roster below is the starting point for that choice, not a lookup table to
copy blindly. Match the model to the actual work:

- how hard is the reasoning, really;
- how much context must the child hold at once;
- does the job lean on web search, long-context reading, or code edits;
- how expensive is a wrong answer here.

Deviate from the roster when the task warrants it, and say why in one line when
you do. A deliberate departure you can justify is better than a default you
did not think about.

## Resolving a model nickname

I refer to models by nickname: "luna", "sol", "opus", "fable", "glm", "k3". A
nickname is not a model id, and you do not know which providers serve it. You
have never seen this machine's registry. Resolve it, every time.

Before launching any subagent, run exactly these two tool calls:

1. `subagent { action: "list", capabilities: true }` — the agents you may run.
2. `subagent { action: "models" }` — ends with "Available models in this
   session's registry". That list is the only authority on which `provider/id`
   pairs exist.

Then match the nickname against that list and pass an exact `provider/id` (plus
`:<thinking>`) from it. Report the id you chose and that you read it from the
registry listing.

The listing is truncated ("... and N more"). Truncation hides models; it never
proves one is missing. If a nickname is absent from the visible part, say the
listing was truncated and ask me — do not conclude it is unavailable.

Never infer model availability from configuration files. `models.json`,
`models-store.json`, `settings.json`, and provider caches are inputs to the
registry, not the registry. A provider absent from `models-store.json` is not
an absent provider; proxy catalogs are discovered at runtime and appear only in
`action: "models"`. Do not grep, read, or reason about those files to decide
what you can launch.

A nickname resolving under several providers is normal. The top-ranked provider
in the roster below that offers that model wins. Substituting a different
provider, or a different model, because you did not find the preferred one in a
config file is a bug.

## Independent review

When both `worker` and `reviewer` run on the same task, they **must use
different model families**. The reviewer exists to supply an independent error
distribution, not another sample from the implementation model.

This constraint binds whatever you pick. If you deviate from the roster on one
side of the pair, re-check that the other side is still a different family.

## Oracle

Consult `oracle` when a decision is important or hard to reverse, several
substantially different solutions are plausible, requirements are ambiguous and
the wrong reading would be costly, agents disagree, you are leaning on an
uncertain assumption, or you want a challenge before committing.

Do not ask `oracle` to rediscover the task or reread a large codebase. It is
the most expensive tier. Hand it a compact decision packet:

- the goal and constraints;
- the relevant facts already established;
- the proposed solution or competing options;
- important assumptions and uncertainties;
- only the minimal code, snippets, or results needed to reason about it;
- the exact question you want challenged.

Use `oracle` to evaluate a decision, never to repeat reconnaissance, research,
or implementation work.

## Delegation patterns

Prefer the smallest useful agent graph:

- simple task → handle directly;
- unclear codebase → `scout` → implement directly or `worker`;
- routine implementation → `worker`;
- research-heavy task → `researcher` → implement → `reviewer`;
- unclear architecture → investigate → `oracle` → implement;
- consequential change → implement → `reviewer`, adding `oracle` when the
  underlying decision itself is uncertain.

After receiving subagent results, integrate and judge them yourself. Subagents
supply evidence and specialized work; they do not transfer responsibility for
the final decision.
