# Pi: Self-Identification ("whoami")

Pi injects `PI_*` environment variables into the agent's shell. To find out
which model you are running as, inspect them (e.g. `env | grep '^PI_'`):

- `PI_PROVIDER` — the provider serving the model (e.g. `ai-proxy`, `opencode-go`).
- `PI_MODEL` — the model id currently in use.
- `PI_REASONING_LEVEL` — the active thinking level.

Subagents receive their own `PI_MODEL`/`PI_PROVIDER` reflecting their launch
override, not the parent's model.

This mechanism applies only to pi. Do not assume other agents (Claude Code,
Codex, etc.) expose the same variables.

The model itself has no intrinsic self-knowledge; identity comes solely from
these variables or from the user stating it.
