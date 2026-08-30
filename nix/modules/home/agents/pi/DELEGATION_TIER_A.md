# Agent Delegation

Default to solving the task yourself. Most tasks are simple enough for one capable model and should not spawn subagents.

Spawn subagents when delegation materially improves correctness, speed, or confidence, especially when:

- the task naturally has multiple stages such as research → implement → verify;
- substantial exploration or independent investigation is needed;
- the solution is unclear and benefits from design/planning before implementation;
- independent review would catch meaningful mistakes;
- work can be usefully parallelized.

Do not spawn agents merely because they are available. Avoid duplicating work that you can do directly and confidently.

## Providers

Prefer providers in this order:

1. ai-proxy
2. opencode-go
3. openrouter

When a preferred model is unavailable from the current providere, first try the
same model from the next provider before substituing a different model.

Never use `openai` or `anthropic` directly unless user explicitly asks for it.

## Subagents

- `scout` — fast codebase reconnaissance: files, entry points, data flow, risks.
  Preferred: **GPT-5.6 Sol, medium**.

- `researcher` — web/docs research, evidence gathering, concise sourced briefs.
  Preferred: **Claude Opus 5, high**; **Kimi K3, max** for very large document/context workloads.

- `worker` — implementation, edits, validation, and tests.
  Preferred: **Claude Opus 5, high**; **GPT-5.6 Sol, high**.

- `reviewer` — independent code/task review, edge cases, tests, simplicity, and small fixes.
  Preferred: **GPT-5.6 Sol, high**; **Claude Opus 5, high**.

- `oracle` — adversarial second opinion for important, ambiguous, or difficult-to-reverse decisions.
  Preferred: **Claude Fable 5, high**.

- `delegate` — lightweight general-purpose delegated work.
  Preferred: **GLM-5.3, medium/max**; **GPT-5.6 Sol, medium**.

**When both `worker` and `reviewer` are used on the same task, they must use different model families.** The reviewer should provide an independent error distribution rather than another sample from the implementation model.

Examples:

- `worker: Claude Opus 5` → `reviewer: GPT-5.6 Sol`
- `worker: GPT-5.6 Sol` → `reviewer: Claude Opus 5`

## Oracle

Consult `oracle` when:

- a decision is important or difficult to reverse;
- multiple substantially different solutions are plausible;
- requirements are ambiguous and choosing the wrong interpretation would be costly;
- other agents disagree;
- you are relying on uncertain assumptions;
- you want an independent challenge before committing.

Do not ask `oracle` to rediscover the task or reread a large codebase. Fable is expensive.

Before consulting it, provide a compact decision packet containing:

- the goal and constraints;
- the relevant facts already established;
- the proposed solution or competing options;
- important assumptions and uncertainties;
- only the minimal code/snippets/results needed to reason about the decision;
- the exact question you want challenged.

Use `oracle` to evaluate the decision, not to repeat reconnaissance or implementation work.

## Delegation Pattern

Prefer the smallest useful agent graph.

Examples:

- simple task → handle directly;
- unclear codebase → `scout` → implement directly or `worker`;
- research-heavy task → `researcher` → implement → `reviewer`;
- unclear architecture → investigate → `oracle` → implement;
- consequential change → implement → `reviewer`, and consult `oracle` when the underlying decision itself is uncertain.

After receiving subagent results, integrate and judge them yourself. Subagents provide evidence and specialized work; they do not transfer responsibility for the final decision.
