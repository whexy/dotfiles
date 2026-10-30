# Agent settings

Use `claude-select`, `codex-select`, or `muse-select` to choose a model gateway
configuration (CLIProxyAPI or magpie), save it, and launch. The searchable terminal UI provides config actions at the
bottom. Ordinary `claude`, `codex`, and `muse` never open a picker, even with a
terminal and no arguments.

## Config manager

Type to search, use the arrow keys to choose, and press Enter to save and
launch. Choose **cliproxyapi (default models)** or **magpie (default models)**
to configure that gateway's endpoint and authentication while clearing previous
model and role overrides. Choose **default (claude.ai login)** or **default
(ChatGPT login)** to remove the gateway overrides and use the agent's own OAuth
login.

`claude-select` also lists every model each gateway's Codex catalog lists when
the picker opens (CLIProxyAPI: `GET /v1/models?client_version=<codexVersion>`;
magpie: `GET /v1/codex/models`), by its catalog display name (falling back to
the model ID). The chosen model fills every Claude Code role; choose **fusion**
to pick a model per role instead, among the main model's gateway. A saved model
stays selected after it leaves the gateway's list, and requests to it fail until
you choose another. When a list cannot be fetched, the picker shows why and
offers only the saved model from that gateway.

Codex lists the selected gateway's models in its own `/model` picker, so
`codex-select` offers one configuration per gateway.

`muse-select` offers the CLIProxyAPI default and every model of the Meta
subscription the proxy holds (`owned_by: meta` in `GET /v1/models`). Muse Code
only speaks to its Meta provider, pointed at the proxy; before it starts it
fetches `{origin}/muse-code/models`, which clusters-work routes to the proxy's
model list. Muse marks the models it fetches that way hidden, so the selector
also writes them as visible `model_catalog` rows, which Muse's own `/models`
picker lists. Activation saves the default on a host with no selection, so Muse
runs through the proxy without a Meta sign-in.

The buttons at the bottom also have shortcuts:

- **Ctrl+S — Switch config:** choose the default or a named config for this launch.
- **Ctrl+N — Fork current config:** name a new config and continue selecting in it.
- **Ctrl+D — Delete current config:** type its name to confirm deletion, then
  return to the default. Close sessions using it first. Default and external
  config directories cannot be deleted.

Switching applies only to the launched process and its descendants. Ordinary
`claude` / `codex` launches still use the default, unless their native config
location environment variable is explicitly set. Escape cancels a menu; a fork
or confirmed deletion already completed remains in effect.

Named configs live under `$XDG_DATA_HOME/agent-settings/<agent>/configs/<name>`
(default `~/.local/share/agent-settings/...`). Forks copy native settings, selector
metadata, instructions, skills, agents, commands, hooks, rules, and Codex profile
TOMLs. Claude's user MCP servers are copied separately. Login files, trust state,
conversation history, caches, and installed plugins are not copied; sign in or
install plugins separately when needed. Credentials manually embedded in copied
settings remain part of those settings. Muse's named configs are exported as
an `XDG_CONFIG_HOME` of their own, since that is the only relocation Muse
honours; its sessions stay shared under the data home.

Nix-managed instructions and Claude's skills directory link through the default
config's paths, so updates and newly added skills follow Home Manager activation.
Claude's skills are shared, including user-installed skills in that directory.
Codex also continues discovering shared user skills in `~/.agents/skills`.
Forked native settings remain separate writable files. Activation always reconciles
the default first, then named configs, preserving valid model choices and user
settings while migrating removed choices to the CLIProxyAPI default.
`CODEX_HOME` and `CLAUDE_CONFIG_DIR` cannot redirect activation.
External config directories are reconciled when selecting a model in them.

## Ownership

- `~/.claude/settings.json`, `~/.codex/config.toml`, and
  `~/.config/muse/settings.json` are writable preferences.
  The selector changes only its model/provider fields and owned environment keys.
  Default login removes those overrides without touching stored login credentials.
- Home Manager activation reconciles named MCP servers and Codex provider
  definitions from Nix. Unknown settings, hooks, plugins, and servers survive.
  TOML comments survive edits. Retired Nix values are removed only when unchanged.
  These entries are maintained defaults, not security enforcement.
- `dotfiles.security.agentPolicy.enable` installs Claude's policy in the native
  managed-settings directory on Darwin and NixOS: the Nix-store permission rules
  and a 1-hour prompt cache TTL. API-key sessions otherwise get 5-minute caches,
  and T3 Code offers to compact a thread once its cache expires. It is enabled by
  the system dev/dev-lite presets. Standalone Home Manager maintains the same user
  settings but cannot enforce system policy. No new Codex sandbox or
  approval restrictions are imposed: add supported requirements through a system
  module when an actual policy is needed, not by making `config.toml` read-only.

`dotfiles-settings.json` beside each agent config records reconciliation ownership
and the credential-selection label. It contains no credential values. Claude and
Codex read API keys and Cloudflare headers from agenix at launch, never written to
native configuration, and a launch with an unavailable secret fails before starting
the agent.

Muse's tools inherit its environment, so Muse gets no credential there. Each
reconciliation instead saves the selected endpoint's key with `muse auth set`
(Muse's own credential store) and its Cloudflare headers in
`endpoint_transport.http_headers` of the mode-0600 `settings.json`, together with
the endpoint they belong to. Its session snapshot leaves the headers out.

## Session inheritance

Fresh launches read the current native config. Descendants inherit a
`DOTFILES_CLAUDE_SESSION` or `DOTFILES_CODEX_SESSION` snapshot of nonsecret launch
selection. Codex descendants receive config defaults before their own arguments;
explicit `--model` and later config overrides remain available. Claude launches
receive one settings override combining their saved launch defaults with the caller's
settings; caller values take precedence. This is necessary
because Claude hot-reloads saved `env` values, which also override shell exports:
a concurrent selector must not redirect a running session's existing API key.
Muse sessions snapshot their model and endpoint the same way, reapplied to
descendant launches as `-c` overrides. An explicit selector resets its
agent's snapshot. CLI arguments and in-app model changes are not recorded in that
snapshot; it represents the launch defaults, not every subsequent session edit.

Environments that strip the snapshot variables fall back to the saved default.
Custom `CODEX_HOME` and `CLAUDE_CONFIG_DIR` directories have independent settings.
Running an upstream binary directly bypasses runtime credential loading.

## Migration and concurrency

Activation removes Home Manager's ownership of the old Claude settings symlink
and reconciles into a regular mode-0600 file. Existing Nix symlinks encountered by
the editor can be materialized; other symlinks are refused. Login files are not
rewritten. Malformed configuration is an error, never an excuse to replace it.
Activation warns with the file's path, leaves that config unreconciled, and
continues; the next activation retries it.

Our writers use advisory locks, same-directory temporary files, fsync, and atomic
replacement. A changed native file is detected before replacement. Upstream agents
do not honor these locks: there remains a small compare/replace race and edits to
several files are not one atomic transaction. Retry a reported conflict rather
than discarding either writer's configuration.

## Development

`withModelPicker.nix` in `modules/home/agents` writes the catalog and wraps each
agent with `agent-settings <catalog> launch|select|sync`. Type checking
(basedpyright) and linting (ruff) are separate flake checks:

```sh
nix build .#checks.aarch64-darwin.pkgs-agent-settings-typecheck --no-link -L
nix build .#checks.aarch64-darwin.pkgs-agent-settings-lint --no-link -L
```

Use the appropriate system attribute on Linux. The dev shell provides the same
tools; from this directory run `basedpyright` and `ruff`.
