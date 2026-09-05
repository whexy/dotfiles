# Agent Delegation

Default to solving the task yourself. Most tasks are simple enough for one capable model and should not spawn subagents.

Spawn subagents only when delegation materially improves correctness, speed, or confidence, especially when:

- the task naturally has multiple stages such as research → implement → verify;
- substantial exploration or independent investigation is needed;
- the solution is unclear and benefits from design/planning before implementation;
- independent review would catch meaningful mistakes;
- work can be usefully parallelized.

Do not spawn agents merely because they are available. Avoid duplicating work that you can do directly and confidently.

## Providers

Every delegated model is served by `openrouter`.

Never use `openai` or `anthropic` directly unless user explicitly asks for it.

## Subagents

- `scout` — fast codebase reconnaissance: files, entry points, data flow, risks.
  Preferred: **GLM-5.3-Flash, medium/high**.
  Escalate to **GLM-5.3, high** for unusually difficult repository analysis.

- `researcher` — web/docs research, evidence gathering, concise sourced briefs.
  Preferred: **Kimi K3, max** for deep or large-context research; **GLM-5.3-Flash, high** for routine research.

- `worker` — implementation, edits, validation, and tests.
  Preferred: **GLM-5.3, high/max** for substantial implementation; **GLM-5.3-Flash, high** for routine changes.

- `reviewer` — independent code/task review, edge cases, tests, simplicity, and small fixes.
  Preferred: **Kimi K3, high/max**; **Muse Spark 1.3, high**.

- `oracle` — adversarial second opinion for important, ambiguous, or difficult-to-reverse decisions.
  Preferred: **Kimi K3, max**.

- `delegate` — lightweight general-purpose delegated work.
  Preferred: **GLM-5.3-Flash, medium/high**.

## Independent Review

When both `worker` and `reviewer` are used on the same task, they **must use different model families**.

The reviewer should provide an independent error distribution, not another sample from the implementation model.

Preferred pairings:

- `worker: GLM-5.3 / GLM-5.3-Flash` → `reviewer: Kimi K3` or `Muse Spark 1.3`
- `worker: Kimi K3` → `reviewer: GLM-5.3` or `Muse Spark 1.3`

Do not use GLM-5.3 and GLM-5.3-Flash as worker/reviewer counterparts; treat them as the same model family for review independence.

## Oracle

Consult `oracle` when:

- a decision is important or difficult to reverse;
- multiple substantially different solutions are plausible;
- requirements are ambiguous and choosing the wrong interpretation would be costly;
- agents disagree;
- important assumptions remain uncertain;
- the design requires unusually strong judgment before committing.

Do not ask `oracle` to rediscover the task or reread a large codebase.

Before consulting it, provide a compact decision packet containing:

- the goal and constraints;
- relevant facts already established;
- the proposed solution or competing options;
- important assumptions and uncertainties;
- only the minimal code, snippets, research results, or test results needed;
- the exact decision or assumption to challenge.

Use `oracle` to reason about the decision, not to repeat reconnaissance, research, or implementation work.

## Delegation Pattern

Prefer the smallest useful agent graph.

Examples:

- simple task → handle directly;
- unclear codebase → `scout` → implement directly or `worker`;
- routine implementation → `worker`;
- research-heavy task → `researcher` → implement → `reviewer`;
- unclear architecture → investigate → `oracle` → implement;
- consequential change → implement → `reviewer`, with `oracle` when the underlying decision is uncertain.

After receiving subagent results, integrate and judge them yourself. Subagents provide evidence and specialized work; they do not transfer responsibility for the final decision.

When launching a subagent, you must explicitly choose a model. Do not rely on default behavior.
