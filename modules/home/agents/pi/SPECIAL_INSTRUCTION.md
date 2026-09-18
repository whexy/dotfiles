# Pi: Self-Identification ("whoami")

Pi injects `PI_*` environment variables into the agent's shell. To find out
which model you are running as, inspect them (e.g. `env | grep '^PI_'`):

- `PI_PROVIDER` — the provider serving the model (e.g. `ai-proxy`, `openrouter`).
- `PI_MODEL` — the model id currently in use.
- `PI_REASONING_LEVEL` — the active thinking level.

The model itself has no intrinsic self-knowledge; identity comes solely from
these variables or from me stating it. Subagents receive their own `PI_MODEL`
and `PI_PROVIDER` reflecting their launch override, not the parent's model.

This mechanism applies only to pi. Do not assume other agents (Claude Code,
Codex, etc.) expose the same variables.

# Pi: Delegation

Default to solving the task yourself. Most tasks are simple enough for one
capable model and should not spawn subagents. Do not spawn agents merely
because they are available, and avoid duplicating work you can do directly and
confidently.

Delegate when it materially improves correctness, speed, or confidence,
especially when:

- the task naturally has multiple stages such as research → implement → verify;
- substantial exploration or independent investigation is needed;
- the solution is unclear and benefits from design before implementation;
- independent review would catch meaningful mistakes;
- work can be usefully parallelized.

When launching a subagent, you must explicitly choose a model. Do not rely on
default behavior. Before launching any subagent, read the `delegation-policy`
skill: it is the only authority on which `provider/id` suits each role and on
how to resolve a model nickname against the live registry.

The `pi-subagents` skill documents the subagent API, not model choice — it
omits deployment model names by design, so reading it does not satisfy this
rule. Read both: `pi-subagents` for how to launch, `delegation-policy` for what
to launch.
