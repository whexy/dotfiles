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

# Pi: Resolving A Model Name

I refer to models by nickname: "luna", "sol", "opus", "fable", "glm", "k3".
A nickname is not a model id, and you do not know which providers serve it.
You have never seen this machine's registry. Resolve it, every time.

Before launching any subagent, run exactly these two tool calls:

1. `subagent { action: "list", capabilities: true }` — the agents you may run.
2. `subagent { action: "models" }` — ends with "Available models in this
   session's registry". That list is the only authority on which
   `provider/id` pairs exist.

Then match the nickname against that list and pass an exact `provider/id`
(plus `:<thinking>`) from it. Report the id you chose and that you read it
from the registry listing.

The registry listing is truncated ("... and N more"). Truncation hides models;
it never proves one is missing. If a nickname is absent from the visible part,
say the listing was truncated and ask me — do not conclude it is unavailable.

Never infer model availability from configuration files. `models.json`,
`models-store.json`, `settings.json`, and provider caches are inputs to the
registry, not the registry. In particular a provider absent from
`models-store.json` is not an absent provider; proxy catalogs are discovered at
runtime and appear only in `action: "models"`. Do not grep, read, or reason
about those files to decide what you can launch.

A nickname resolving under several providers is normal. Apply the provider
preference order in the delegation rules below; the top-ranked provider that
offers that model in the registry listing wins. Substituting a different
provider, or a different model, because you did not find the preferred one in
a config file is a bug.
