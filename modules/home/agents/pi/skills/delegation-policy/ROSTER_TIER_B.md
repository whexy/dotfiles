## Providers

Every delegated model on this host is served by `openrouter`. The AI proxy is
not configured here, so `ai-proxy/*` ids do not resolve — do not reach for them.

Never use `openai` or `anthropic` directly unless I explicitly ask for it.

## Subagents

- `scout` — fast codebase reconnaissance: files, entry points, data flow, risks.
  Preferred: **GLM-5.3-Flash, medium/high**.
  Escalate to **GLM-5.3, high** for unusually difficult repository analysis.

- `researcher` — web/docs research, evidence gathering, concise sourced briefs.
  Preferred: **Kimi K3, max** for deep or large-context research;
  **GLM-5.3-Flash, high** for routine research.

- `worker` — implementation, edits, validation, and tests.
  Preferred: **GLM-5.3, high/max** for substantial implementation;
  **GLM-5.3-Flash, high** for routine changes.

- `reviewer` — independent code/task review, edge cases, tests, simplicity, and
  small fixes.
  Preferred: **Kimi K3, high/max**; **Muse Spark 1.3, high**.

- `oracle` — adversarial second opinion for important, ambiguous, or
  difficult-to-reverse decisions.
  Preferred: **Kimi K3, max**.

- `delegate` — lightweight general-purpose delegated work.
  Preferred: **GLM-5.3-Flash, medium/high**.

## Independent Review

**GLM-5.3 and GLM-5.3-Flash are one model family.** Never pair them as worker
and reviewer; they do not provide independent error distributions.

Preferred pairings:

- `worker: GLM-5.3 / GLM-5.3-Flash` → `reviewer: Kimi K3` or `Muse Spark 1.3`
- `worker: Kimi K3` → `reviewer: GLM-5.3` or `Muse Spark 1.3`

Delegation is more expensive relative to solving the task yourself here than on
a proxy host. Spawn subagents only when delegation materially improves
correctness, speed, or confidence.
