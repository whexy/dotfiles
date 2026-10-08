# Pi: Self-Identification ("whoami")

Pi injects `PI_*` environment variables into the agent's shell. To find out
which model you are running as, inspect them (e.g. `env | grep '^PI_'`):

- `PI_PROVIDER` — the provider serving the model (`cliproxyapi`).
- `PI_MODEL` — the model id currently in use.
- `PI_REASONING_LEVEL` — the active thinking level.

The model itself has no intrinsic self-knowledge; identity comes solely from
these variables or from me stating it.

This mechanism applies only to pi. Do not assume other agents (Claude Code,
Codex, etc.) expose the same variables.
