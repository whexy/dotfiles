# Agent settings

Use `claude-select` or `codex-select` to choose a provider/model (or the native
login default), save it, and launch. Claude's selector also supports per-role
fusion selection. Cancellation changes nothing. Ordinary `claude` and `codex`
never open a picker, even with a terminal and no arguments.

## Ownership

- `~/.claude/settings.json` and `~/.codex/config.toml` are writable preferences.
  The selector changes only its model/provider fields and owned environment keys.
  Default login removes those overrides without touching stored login credentials.
- Home Manager activation reconciles named MCP servers and Codex provider
  definitions from Nix. Unknown settings, hooks, plugins, and servers survive.
  TOML comments survive edits. Retired Nix values are removed only when unchanged.
  These entries are maintained defaults, not security enforcement.
- `dotfiles.security.agentPolicy.enable` installs Claude's Nix-store permission
  rules in the native managed-settings directory on Darwin and NixOS. It is
  enabled by the system dev/dev-lite presets. Standalone Home Manager maintains
  the same user rules but cannot enforce system policy. No new Codex sandbox or
  approval restrictions are imposed: add supported requirements through a system
  module when an actual policy is needed, not by making `config.toml` read-only.
- cmux owns per-launch instrumentation. Its injected arguments pass through and
  are never saved as preferences. Selectors inside cmux invoke its bundled wrapper
  with the Nix noninteractive launcher as the target.

`dotfiles-settings.json` beside each agent config records reconciliation ownership
and the credential-selection label. It contains no credential values. API keys
and Cloudflare headers are read from agenix at runtime, never written to native
configuration. A launch with an unavailable secret fails before starting the agent.

## Session inheritance

Fresh launches read the current native config. Descendants inherit a
`DOTFILES_CLAUDE_SESSION` or `DOTFILES_CODEX_SESSION` snapshot of nonsecret launch
selection. Codex descendants receive config defaults before their own arguments;
explicit `--model` and later config overrides remain available. Claude launches
receive one settings override combining their saved launch defaults with the caller's
settings (including cmux hooks); caller values take precedence. This is necessary
because Claude hot-reloads saved `env` values, which also override shell exports:
a concurrent selector must not redirect a running session's existing API key.
An explicit selector resets its
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

Our writers use advisory locks, same-directory temporary files, fsync, and atomic
replacement. A changed native file is detected before replacement. Upstream agents
do not honor these locks: there remains a small compare/replace race and edits to
several files are not one atomic transaction. Retry a reported conflict rather
than discarding either writer's configuration.

Run the isolated regression suite with:

```sh
nix build .#checks.aarch64-darwin.agent-settings --no-link -L
```

Use the appropriate system attribute on Linux. Tests use temporary homes and fake
agent launches, never real credentials or paid model requests.
