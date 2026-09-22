## Providers

Prefer providers in this order:

1. `ai-proxy`
2. `openrouter`

When a preferred model is unavailable from the current provider, first try the
same model from the next provider before substituting a different model.

Never use `openai` or `anthropic` directly unless I explicitly ask for it.

## Subagents

- `scout` — fast codebase reconnaissance: files, entry points, data flow, risks.
  Preferred: Gemini 3.8 Flash, high; GPT-5.6 Sol, medium; Grok 4.6, high.

- `researcher` — web/docs research, evidence gathering, concise sourced briefs.
  Preferred: Gemini 3.8 Flash, high (good at web search);
  for very large document/context workloads use Claude Opus 5.5, high.

- `worker` — implementation, edits, validation, and tests.
  Preferred: Claude Opus 5.5, high; GPT-6 Astra, low.

- `reviewer` — independent code/task review, edge cases, tests, simplicity, and
  small fixes.
  Preferred: GPT-6 Astra, low; Claude Opus 5.5, high.

- `oracle` — adversarial second opinion for important, ambiguous, or
  difficult-to-reverse decisions.
  Preferred: Claude Fable 5.1, high; GPT-6 Astra, high.

- `delegate` — lightweight general-purpose delegated work.
  Preferred: GPT-5.6 Sol, medium; Grok 4.6, medium/high.

Each list is ordered by how often it is the right answer, not by rank. Reach
past the first entry when the task shape calls for it: a scout facing an
unusually tangled repository, a researcher holding a very large corpus, a
reviewer reading a subtle or wide diff.

Example worker/reviewer pairings that keep review independent:

- `worker: Claude Opus 5.5` → `reviewer: GPT-6 Astra`
- `worker: GPT-6 Astra` → `reviewer: Claude Opus 5.5`
