Dotfiles is my personal system definition and configs managed by Nix.
The repo contains NixOS, nix-darwin, and Home Manager configs.

## Layout

- `/hosts` - Blueprint host definitions
- `/modules/hosts` - semantic system setting groups shared by NixOS and Darwin
- `/modules/caps` - system capability preset modules
- `/modules/home` - semantic Home Manager software groups
- `/modules/home/caps` - Home Manager capability preset modules
- `/overlays` - nixpkgs overlays

### System configs

System features are grouped semantically, like settings categories. A group
may contain related options for both platforms; platform-specific behavior
still belongs to that semantic group. For example, passwordless sudo,
1Password, fail2ban, and macOS biometric sudo all belong to `security`.

Each group follows this pattern:

- `modules/hosts/<group>/default.nix` - declares `dotfiles.<group>.*`
  options (every option has a default)
- `modules/hosts/<group>/nixos.nix` - NixOS config gated by those options
- `modules/hosts/<group>/darwin.nix` - Darwin config gated by those options

`modules/hosts/nixos.nix` and `darwin.nix` recursively aggregate the
matching files and exclude the other platform. Platforms, images, user setup,
and custom hardware metadata are option-driven groups under this same tree;
there are no separate `modules/nixos` or `modules/darwin` directories.

### Home configs

Home features represent software, grouped when related. Examples:

- `terminal` groups Ghostty, tmux, and zellij
- `editor` groups Neovim and Neovide
- `vcs` groups git and delta
- `wm` groups niri and aerospace
- `keyboard` groups fcitx5 and Karabiner

A group's `default.nix` declares its `dotfiles.<group>.*` options and imports
its config files; config is gated with `lib.mkIf`. Standalone software can put
options and config together in its own `default.nix`. `homeModules.all`
aggregates all feature modules, while presets under `modules/home/caps`
are imported selectively.

## Capabilities

Caps describe machine roles (`base`, `dev`, `dev-lite`, `gui`, `service`, and
the home-only `sysadmin` and `agent`), but **caps are not options or
features**. They are preset modules:

- `modules/caps/<cap>.nix` assigns system `dotfiles.*` options
- `modules/home/caps/<cap>.nix` assigns Home Manager software options and
  cap-specific package lists

Feature option defaults have the lowest priority. Importing a cap assigns
preset values with `lib.mkDefault`, so a host or user customizes the preset
with a plain assignment, for example:

```nix
dotfiles.virtualization.docker.enable = false;
```

`lib.mkForce` is only needed to override a value a feature module assigns at
normal priority.

A cap should only tune feature options; implementation remains in semantic
feature groups. Platform-specific options may be enabled by the same preset
and simply have no config on the other platform.

## Putting them together

Blueprint discovers hosts from `hosts/<name>`. NixOS hosts use
`configuration.nix`; Darwin hosts use `darwin-configuration.nix`. Both are
blueprint's native loaders, so blueprint wires Home Manager for every host: it
imports the HM module, discovers users from
`hosts/<name>/users/<user>/home-configuration.nix`, injects `perSystem` into OS
and HM modules, and enables `useGlobalPkgs`/`useUserPackages`. Hosts with only a
`users/` tree (e.g., venus, mars) become standalone
`legacyPackages.<system>.homeConfigurations."<user>@<host>"`.

Host files call `flake.lib.nixosHost` or `flake.lib.darwinHost` with their local
`system`, `hostName`, `caps`, optional extra `modules`, and optional extra
`overlays`. The helpers import the selected system cap presets, expose host
metadata as `config.dotfiles.host.*`, set `nixpkgs.hostPlatform`/`overlays`,
and wire the semantic system feature aggregator. `darwinHost` additionally
overrides `nixpkgs.pkgs` to keep Darwin hosts on the `nixpkgs-darwin` branch
(blueprint's injected pkgs comes from the NixOS-branch `nixpkgs` input).

Integrated users import `homeModules.host-user`, which imports
`homeModules.all` and the matching Home Manager cap presets via
`flake.lib.homeCapsModules`; cap names arrive as a special argument, not a
config option. Home modules read global system options directly from
`osConfig.dotfiles.*`; do not mirror them into separate HM options.
Standalone homes import `homeModules.all` plus `homeCapsModules [ ... ]`
directly.

Do not set `nixpkgs.config` in system modules: blueprint configures nixpkgs at
the flake level (`flake.nix`) and injects `nixpkgs.pkgs`, and the module system
asserts `nixpkgs.config == { }` when `nixpkgs.pkgs` is set. Host-specific
hardware lives beside the host as `hardware.nix`; reusable platform and image
behavior is selected with `dotfiles.platform.*` and `dotfiles.image.*`.

## Private flake fetches

`dotfiles.nix.ghTokenFlakes` (home, on the `dev` and `dev-lite` caps) lets
`nix run github:whexy/<private>` work without a stored secret. Activation runs
`nix-gh-token`, which writes the `gh` CLI token into
`~/.config/nix/gh-token.conf`; the Home Manager-owned `nix.conf` pulls it in
with `!include`. Without a `gh` login nothing is written, and everything
behaves as if the feature were off.

Tokens are bound to owner scopes (`github.com/whexy`), never bare
`github.com`, so a stale token can only break fetches under that owner rather
than every _public_ flake fetch. A rejected token still fails those fetches
with HTTP 401 (Nix does not fall back to anonymous access), which is why
`nix-gh-token` probes the token against the API and drops the fragment when
GitHub rejects it with 401. Any other outcome (offline, keyring still locked at
boot, `gh` logged out) leaves an existing fragment in place. The Home Manager auto-upgrade daemon also fetches under
`github.com/whexy`, so it clears `access-tokens` for its own Nix calls: a stale
fragment must not block the activation that would refresh it, which only works
while the upgrade source and all its inputs stay public. Keep the fragment out
of `nix.settings`/git, and refresh it by re-running activation after
`gh auth login`.

## T3 Code server

The server listens only on loopback, at port 3773. On tailnet hosts
(`dotfiles.agents.t3code.server.tailnet.enable`, on by default wherever
`dotfiles.network.tailscale` is), Tailscale Serve also publishes it at
`https://<MagicDNS name>:35338`. Every server is published on the public
internet by its own tunnel (below).

Standalone homes have no `osConfig`, so a standalone host that runs the
server enables it, its tailnet route, and `server.tunnel.hostName` itself
(b3srv0, off the tailnet; proxmox, on it). Its user services start at boot
only with lingering, which the auto-upgrade module turns on.

### Public tunnel

Every server is published on the public internet at
`https://<host>-t3.clusters.work` by the `t3code-tunnel` user service, which
runs the tunnel `t3-<host>` (`server.tunnel.enable`, on by default wherever the
server runs; see [Public tunnels](#public-tunnels)).

The server's own pairing is the only gate. There is no Cloudflare Access on
these names: the mobile app cannot sign in to it, and the web client's
cross-origin requests would be redirected to its login page.

Pair hosts with `t3-pair`, which prefers the public URL whenever it answers. A
client paired over the public URL learns the server's Tailscale route and puts
it first, so it stays on the tailnet where that works and falls back to the
tunnel elsewhere. Paired over Tailscale, a client never learns the public URL,
because servers report only their LAN and Tailscale addresses.

## Spark MCP server

`packages/spark-mcp` serves the email-reading tools of Spark Desktop's stdio
MCP server (`spark mcp`) over Streamable HTTP, at `POST /mcp`, and rejects
every other Spark tool. Each request spawns its own `spark mcp`, so the server
holds no state.

sheridan runs it (`dotfiles.agents.spark.server.enable`) as the `spark-mcp`
launchd agent on loopback port 8765. The `spark-mcp-tunnel` agent publishes
only `/mcp`, at `https://sheridan-spark.clusters.work/mcp` (tunnel
`spark-sheridan`).

- `spark mcp` talks to the Spark Desktop app in the user's GUI session, so the
  server is a user agent and answers only while the app runs.
- Run the CLI through the `/usr/local/bin/spark` symlink, never by the path it
  resolves to: from inside the app bundle it cannot reach the app.

A Cloudflare Access application in the Zero Trust dashboard (not in git)
covers the hostname, with Managed OAuth on. MCP clients that speak OAuth, such
as ChatGPT and Claude.ai connectors, register themselves with Access and sign
the owner in through its identity provider; other clients send an Access
service token. The server verifies the Access JWT on every request against
the team domain and the application's AUD tag (`server.accessAud`), so it has
no credentials of its own.

## SimpleStudio MCP server

`dotfiles.agents.studio` (on the `dev` cap, and wherever `video` is) registers
SimpleStudio's MCP server, `https://studio-mcp.clusters.work/mcp`, with every
agent. Its tools generate video on the studio's GPU Workers, and the `broll`
skill fills B-roll slots with that footage.

Cloudflare Access is the server's OAuth provider. Studio acts as the account
whose email the sign-in names and refuses service tokens, so each agent signs
the owner in itself, once per machine:

- Claude Code: `claude mcp login studio`
- Codex: `codex mcp login studio`
- OpenCode: `opencode mcp auth studio`

Over SSH, pass `--no-browser` to Claude Code or Codex and paste the redirect
URL back. T3 Code's sessions use the same token stores. Each agent registers
its own loopback callback with Access, so the Access application needs no
redirect URIs for them.

## Public tunnels

Each service a host publishes on the public internet gets its own Cloudflare
tunnel, at `https://<host>-<service>.clusters.work` (`flake.lib.publicHost`,
the single place these names are defined). `modules/home/agents/tunnel.nix`
runs each tunnel as a user service to the service's loopback port, so traffic
never passes through the cluster.

No host is set up by hand. Every host decrypts the same `cloudflared-cert`
secret, the cert from one `cloudflared tunnel login` for the zone. On start a
tunnel service creates its tunnel (or recovers its credentials into
`~/.local/state/<service name>/` when the tunnel already exists), points the
DNS name at it, and runs it. The cert can create tunnels and edit every DNS
record in the zone; it adds little to what the shared agenix key already
exposes on each host.

## Verification

(Before verification, remember to use `git add` to add new files, as flake
only see files tracked by git.)

Run `just verify` to check all flake outputs evaluate correctly.
Run `just check` to run formatters and linters checklists.

## Dev environment

A `devShell` provides the formatters and linters on `PATH` (treefmt, nixfmt,
statix, nil, nixd, deadnix, stylua, prettier, shfmt, taplo).

Enter it with `nix develop`, or automatically via `direnv allow` (uses
`.envrc`). Entering the shell installs git pre-commit hooks (`git-hooks.nix`)
that run treefmt + statix + nil + deadnix before each commit. The same checks
run in CI via `nix flake check` / `just check` (`checks.<system>.pre-commit`).

Formatter definitions live in `treefmt.nix` (single source of truth, shared by
`nix fmt`, the pre-commit hook, and the flake check).
