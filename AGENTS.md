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
- `editor` groups Neovim, Neovide, and VS Code
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

## Skills

An agent skill is a directory holding a `SKILL.md`. Every agent sees the
same skills, linked into `~/.agents/skills`, `~/.claude/skills` and
`~/.config/muse/skills`. Claude Code keeps the skills it syncs from the
account in `~/.claude/skills/synced/`, so no skill may be named `synced`.

A package ships its skills at `$out/share/skills/<name>/SKILL.md`, the way it
ships `bin/` or `share/man/`. Our own packages keep them in
`packages/<pname>/skills/`, left out of the build source with `lib.fileset`
and copied in at install, so editing a skill does not rerun the tool's
checks.

`dotfiles.agents.skills` decides what agents see:

- `packages`: packages whose `share/skills` agents read; never the whole home
  profile.
- `local.<name> = { source; reason; }`: skills written in this repo. Each
  directory in `modules/home/agents/skills/` is one.
- `override.<name>`: changes a skill a listed package provides, with exactly
  one of `patches` (applied with `patch -p1 --fuzz=0`), `replace` or
  `ignore = true`.
- `docs.<name> = path`: trees a skill reads by path, at
  `~/.local/share/video-edit/docs/<name>`. They are not skills; a package's
  skills read this way are ignored as skills.

Every deviation from a package's skill carries a reason: `override` requires
one, and a `local` skill that stands in for one a tool would install itself
sets one. Each feature adds its skills in `modules/home/agents/default.nix`,
in the same gate as the CLI it installs. A feature that overrides skills keeps
its settings in its own file (`cloudflare/skills.nix`, `iphone/skills.nix`,
`video/home.nix`), which `checks/agent-skills` imports too.

| Skill                                     | Source                     | Taken                                         |
| ----------------------------------------- | -------------------------- | --------------------------------------------- |
| `modules/home/agents/skills/*`            | local                      | ours                                          |
| `transcribe`, `wechat`                    | `transcribe`, `wechat-cli` | as shipped                                    |
| `video-edit`, `broll`                     | local, video feature       | ours; they drive several tools                |
| `reverse-engineer-anything`, `iphone-use` | `rea-agents`, `iphone-use` | as shipped                                    |
| `iphone-use-setup`                        | `iphone-use`               | replaced by `iphone/iphone-use-setup`         |
| `cf-cli`                                  | `cf`                       | patched by `cloudflare/cf-cli-skill.patch`    |
| `asc`, `spark`                            | local, with a reason       | the tools generate theirs at runtime          |
| HyperFrames' skills, ManimGX's skill      | `hyperframes`, `manimgx`   | ignored; `broll` reads them by path as `docs` |

Our packages of third-party tools copy every skill upstream publishes into
`share/skills`, and leave upstream's own copy where its code reads it. Each
one agents do not see is ignored with a reason, so a skill an upstream bump
adds or drops fails `checks/agent-skills` until it is accounted for. cf's
npm tarball ships no skill, so cf takes its own, `cf-cli`, from Cloudflare's
separate skills repository and none of that repository's product guides.

`build-skills.nix` assembles the tree in one derivation. It fails on a listed
package without skills, two sources for one name, an override no package
provides, a patch that does not apply, a `docs` tree that reads a skill agents
see, and a `SKILL.md` whose frontmatter `name` is not its directory or whose
`description` is empty.

`checks/agent-skills` builds every skill in the repo at once and compares the
exposed names with the list written in it. The nightly update builds it for
each package that ships skills, so an upstream bump that breaks a patch holds
back only that package. Changing which skills agents see means changing that
list.

```sh
nix build .#checks.x86_64-linux.agent-skills
```

## Secrets

A secret lives in agenix or in 1Password:

- agenix holds what the system itself needs to boot, evaluate, or activate
  (Rex's netrc, Beszel's token, the tunnels' cert), encryption keys such as
  Atuin's, and each home's 1Password service-account token.
- 1Password holds the credentials tools use: API keys, access tokens, and
  client certificates. A tool loads them when it runs.

### agenix

agenix secrets live in `secrets/`, encrypted to one key per machine;
`secrets/secrets.nix` lists each file's recipients. System secrets
(`age.secrets` in NixOS and nix-darwin) decrypt with the host key,
`/etc/ssh/ssh_host_ed25519_key`. A Home Manager user cannot read that key, so
it decrypts with `~/.ssh/agenix_ed25519`, generated on that machine and never
copied; root homes use the host key. `modules/home/all.nix` sets this identity
for every home.

The agenix CLI only looks for `~/.ssh/id_ed25519` and `~/.ssh/id_rsa`, so pass
the identity to every command, run from `secrets/`:

```sh
agenix -e beszel-token.age -i ~/.ssh/agenix_ed25519
```

To add a machine, generate its key there:

```sh
ssh-keygen -t ed25519 -N "" -f ~/.ssh/agenix_ed25519
```

On WSL, `ssh-keygen` is Windows' `ssh-keygen.exe`, which cannot write into
the Linux home; run `/run/current-system/sw/bin/ssh-keygen` instead.

Add its `.pub` to `secrets/secrets.nix` (a NixOS or nix-darwin host also adds
`/etc/ssh/ssh_host_ed25519_key.pub`; a root home adds only the host key). Then
rekey on mudd or sheridan, the editors that can decrypt every file:

```sh
agenix -r -i ~/.ssh/agenix_ed25519
```

Dropping a recipient does not revoke what that machine already decrypted;
rotate the secret too. Then give the home a 1Password service account (below).

### 1Password

A tool loads its key when it runs, with `op-sa read <name>`, and passes it to
that one process; no copy is kept. `modules/home/onepassword/items.nix` maps
each name to its 1Password item.

The items live in two vaults, by who reads them: `dotfiles` for every home,
`dotfiles-dev` for every home but root's. Each home signs in as its own
service account, `dotfiles <user>@<host>`, which can only read those vaults.
Its token is `secrets/onepassword-<user>-<host>.age`, for that home and the
editors. Standalone homes name their account with
`dotfiles.onepassword.serviceAccount`.

All service accounts share the 1Password account's 1,000 requests a day, and
each read of a name costs one: `items.nix` names vaults and items by ID, which
1Password reads in one request instead of three. A tool that runs
continuously loads its keys once, not on every use.

`op-sa` also takes a pasted item ID for a one-off task, finding the vault
itself, without printing the value: `show` lists its fields, `run` gives a
command the secret in its environment and masks it in the output, and `read`
prints it into a pipe or file. The `op-sa` skill teaches agents to use it.

To rotate a credential, put the new value in its item. Each tool uses it from
its next run.

To add a credential, create its item in the vault of the homes that read it,
add its reference to `items.nix`, and load it with `op-sa read` where the
tool starts.

To give a home its service account, sign in with `eval $(op signin)` and run,
from `secrets/` (a root home leaves out `dotfiles-dev`):

```sh
token=$(op service-account create "dotfiles whexy@<host>" \
  --vault dotfiles:read_items --vault dotfiles-dev:read_items --raw)
printf %s "$token" | age -o onepassword-whexy-<host>.age -R <(
  nix eval --raw -f secrets.nix '"onepassword-whexy-<host>.age".publicKeys' \
    --apply 'builtins.concatStringsSep "\n"'
)
```

To cut off a home, delete its service account on 1Password.com. It then reads
nothing more, unlike a dropped agenix recipient.

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

## Cloudflare CLI

The `dev` and `dev-lite` caps install `cf`, Cloudflare's CLI
(`packages/cf`, also run as `cloudflare`), and give every agent Cloudflare's
`cf-cli` skill. No host runs `cf auth login`: `cf` signs in with one scoped API
token, the 1Password item `cloudflare-api-token`
(`dotfiles.tooling.cloudflare.apiToken`).

- `cf`'s wrapper loads the token on each run and exports it, with the
  token's account (`CLOUDFLARE_ACCOUNT_ID`), to that `cf` process alone. No
  shell or agent environment holds it.
- A token the caller brings wins: one already in the environment, or one in
  the `.env` that `cf` reads from the current directory.
- When the token cannot be loaded, `cf` runs signed out.

Inside a project that depends on `cf`, the global command hands off to the
project's npm-installed copy. On NixOS its prebuilt workerd (`cf dev`) runs
through nix-ld, which the `dev` cap enables.

### Provision the token

1. In the Cloudflare dashboard, under Manage Account → Account API Tokens,
   create a custom token for the account in `modules/home/tooling/cloudflare.nix`.
   Grant only what agents should do; reading is enough to start:
   Account Settings Read, Zone Read, DNS Read, and Workers Scripts Read, on
   all zones in the account. Editing the token's permissions later keeps its
   value, so the secret does not change.
2. Paste it as the credential of the item `Cloudflare API token (cf)` in the
   `dotfiles-dev` vault.
3. `cf auth whoami` then reports `"tokenValid": true`.

To rotate, roll the token in the dashboard and repeat steps 2 and 3.

## AWS CLI

The `dev` and `dev-lite` caps install AWS CLI v2
(`dotfiles.tooling.aws.enable`). Its default profile uses `credential_process`
to read `aws-credentials` from 1Password when credentials are needed. The
`AWS dotfiles` item's `credential` field in `dotfiles-dev` holds JSON with
`Version` set to `1`, `AccessKeyId`, and `SecretAccessKey`. No key is written
to `~/.aws/credentials` or the shell environment.

Verify access with `aws sts get-caller-identity --region us-east-1`. No default
region is set; pass `--region`, set `AWS_DEFAULT_REGION`, or declare
`programs.awscli.settings.default.region` in the home config. Existing AWS
environment credentials take precedence over the default profile's process.
To rotate, replace the key pair in the 1Password item's JSON.

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

### Gateway models for Claude

T3's Claude model picker also lists every non-Claude model CLIProxyAPI serves,
with the reasoning levels Claude Code accepts. `t3-claude-models` writes them
into `~/.t3/userdata/settings.json` as custom models of T3's `claudeAgent`
provider. Activation runs it; run it yourself to pick up a changed catalog.
While the gateway or its secrets are unavailable, the list stays as it was.

T3 starts Claude Code through the `claude` launcher, so these models go to the
gateway `claude-select` saved. They work only while that is CLIProxyAPI, the
default.

Custom models added in T3 itself survive a refresh: `dotfiles-settings.json`
beside T3's settings records the models `t3-claude-models` wrote.

### Desktop app

The `gui` cap installs the T3 Code desktop app
(`dotfiles.agents.t3code.desktop.enable`). On Linux it is
`t3code-desktop-nightly`, pinned with the server, with its own updater off. On
macOS, activation installs `/Applications/T3 Code (Nightly).app` only when it
is missing, and the app updates itself.

The app's bundled server needs `~/.t3/userdata` to itself; while the server
service holds it, the app reports "This T3 home is unavailable" and quits.
Wherever the service runs, activation therefore turns off the app's local
environment (`localEnvironmentEnabled` in `desktop-settings.json`), and the app
is a client of that server. Pair it once: run `t3-pair` and paste the link
under Settings → Connections → Add environment.

## Muse Code

Muse Code runs on the Meta subscription CLIProxyAPI holds, so no host signs in
to Meta. Muse only speaks to its Meta provider, which agent-settings points at
`https://llm.clusters.work/v1`; `muse-select` lists the subscription's models,
and activation saves the default wherever no selection exists.

- Muse will not start until `{origin}/muse-code/models` answers. CLIProxyAPI
  has no such path, so the clusters-work route for `llm.clusters.work` rewrites
  it to `/v1/models`. Requests for Meta's other services, such as its web
  search (`/muse-code/search`), get the gateway's 404.
- Muse's tools inherit its environment, so its credentials never go there:
  activation stores the CLIProxyAPI key with `muse auth set` and writes the
  Cloudflare Access headers into `~/.config/muse/settings.json`.

## Rex remote access

Rex clients reach a host at `https://<MagicDNS name>:7297`
(`dotfiles.network.tailscale.rex`), the port they try for a bare host name. Rex
for iOS still asks for an account, so add a host as `<user>@<MagicDNS name>`.

On Macs (the `gui` cap), Tailscale Serve forwards to the Rex app's server. Rex
has no authentication, and this route keeps it from identifying callers:

- The app fixes its server's command line, listening only on its Unix socket,
  so the route forwards to that socket. Rex treats a caller there as the user,
  so the tailnet ACL is the only gate: every device it lets reach the Mac on
  that port gets a shell.
- tailscaled serves a Unix socket only for root, so system activation sets the
  route, and removes it once the option is off.

On NixOS (the `dev` cap), Rex's login server serves the route. It learns each
caller's Tailscale login from tailscaled and admits only `whexy@github`, as the
primary user. WSL has no server: the Windows client there cannot name callers.

There is no public tunnel: without authentication in Rex, one would give anyone
a shell.

### The rex input

The login server comes from the `rex` flake input, which pkgs.superlogical.com
serves only with Rex's testing token until Rex's first release. Every NixOS
evaluation imports Rex's module, so every system host decrypts the token into
Nix's netrc (`dotfiles.nix.rexNetrc`, on the `base` cap); homes never fetch the
input.

In CI, the update lane and the check on master read the token from the
Woodpecker secret `rex_package_token`. A pull-request check has no token and
substitutes the input from the CI cache, so a pull request that moves the `rex`
lock fails its check. A new token goes into both `rex-package-netrc.age` and
that secret.

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
- Muse Code: `muse mcp login studio`

Over SSH, pass `--no-browser` to Claude Code or Codex (`--headless` to Muse
Code) and paste the redirect URL back. T3 Code's sessions use the same token stores. Each agent registers
its own loopback callback with Access, so the Access application needs no
redirect URIs for them.

## iPhone automation

`dotfiles.agents.iphoneUse` (golf, mudd, deimos, sheridan) gives every agent
iPhone Use's tools for the phones in `modules/home/agents/iphone/phones.nix`.

Each phone runs WebDriverAgent on its own: it is launched as an installed app,
not by xcodebuild, so it keeps serving after the launcher exits and with no
computer attached. It listens only on the phone's Tailscale address
(`USE_IP`), and it has no authentication, so the tailnet ACL is the only gate:
whoever reaches port 8100 controls the unlocked phone. Its screen stream on
port 9100 ignores `USE_IP` and stays open on every network the phone joins.

Agents reach a phone through `iphone-use-select`, an MCP proxy in front of
iPhone Use:

- A session starts with no phone; the agent asks the user which one to use.
- The proxy forwards a loopback port to that phone, because iPhone Use talks
  only to loopback.
- iPhone Use's xcodebuild setup tools are hidden.
- Two agents on one phone end each other's sessions, because WebDriverAgent
  keeps only one.

`iphone-wda` launches the runner. It needs a host that reaches the phone's
developer services, today a Mac paired with the phone (golf, over Wi-Fi). Run
it after the phone restarts, with the phone unlocked:

```sh
iphone-wda launch iphone-17-pro
```

On iOS 27 the runner must start in the background, through CoreDevice process
control with `ActivateSuspended`; `devicectl` cannot launch it. pymobiledevice3,
which does this, comes from PyPI, hash-pinned in
`packages/iphone-wda/requirements.txt`: nixpkgs' copy does not evaluate on
Darwin.

To add a phone:

1. On the phone, turn on Developer Mode and Settings → Developer → Enable UI
   Automation, install Tailscale, and pair it with a Mac in Xcode. Let the
   agent hosts reach it on TCP 8100 in the tailnet ACL.
2. Add it to `phones.nix` (`iphone-wda devices` on the Mac shows its device
   name) and switch.
3. In a terminal on that Mac, run `iphone-wda build --register <phone>`, then
   `iphone-wda install <phone>` and `iphone-wda launch <phone>`. Over SSH the
   build cannot sign: those sessions see the login keychain as locked.

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
record in the zone, so only homes that run a tunnel can decrypt it (see
[Secrets](#secrets)).

## Package updates

A package that fetches an upstream release declares how it is updated, as
data in `passthru.updater`, built with `flake.lib.updater` (`lib/updater.nix`,
which rejects a missing or unknown field at evaluation). A package that stays
frozen sets `passthru.updater = null;` with a comment saying why. Updatable
packages set `meta.changelog`, which their update commits link to.

The kinds, cheapest first:

- `nix-update`: runs `nix-update --flake <name>` with the package's `args`.
  Pins stay inline.
- `npm`: an npm registry tarball. Bumps it with nix-update, regenerates the
  vendored package-lock.json from package.json after `lockfileFilter`, the
  jq filter the package's `postPatch` also applies, and re-pins `npmDepsHash`.
  `prebuilds` names dependencies whose install script downloads a prebuilt
  archive (`urlTemplate`, `platforms`); their pins in `sources.json` follow
  each dependency's version in the lockfile, and the package hands the
  archive to the install script.
- `platform-binaries`: one prebuilt archive per platform, from
  `versionSource`, `urlTemplate` and `platforms`; downloads each to hash it.
- `manifest-checksums`: per-platform binaries whose hashes the vendor's
  manifest lists, so nothing is downloaded.
- `script`: the package's own `update.py`, written with the `updater` library
  in `packages/update`; it reads its `settings` from the config.

The last three write `sources.json`, which the package reads with
`lib.importJSON`. Any kind can also take `subpackages` (passthru fetchers
whose hash follows the version), `followBranch` (passthru git fetchers that
move to their default branch's head with the package), `alsoBuild` (packages
that read this one's pins) and `allowDowngrade`.

`checks.<system>.package-updaters`, which CI and `just verify` build, fails
when a package fetches an upstream source without a `passthru.updater`, or
has an updater but no `meta.changelog`.

`nix run .#update` updates every such package; name packages to update only
those, and `--list` shows them. The driver builds each updated package and
its `alsoBuild` on this system and evaluates them on the others; when one of
them ships `share/skills`, it also builds `checks.<system>.agent-skills`. A
package that fails is restored and reported, the rest continue, and the run
exits non-zero. To test an updater, downgrade the package's pin and run it:

```sh
nix run .#update -- muse-code
```

The nightly `update` step in `.woodpecker.yml` runs `nix flake update`, then
`nix run .#update -- --commit`, which commits each package as
`chore(<name>): <old> -> <new>`, and pushes after the shared check.

## CI repair

When a pipeline on master fails (a push's check, the update lane, or the T3
hub publish), its last step, `report-failure`, posts the failure to a webhook
task on mudd's T3 Code server, "Repair a failed dotfiles pipeline". The task
starts an agent run in the Dotfiles project that reruns a transient failure,
or ships a fix as a rebase-merged pull request and reruns the update lane, so
the packages it reverted update. Pull requests are not reported.

- The task's webhook URL is the Woodpecker secret `t3_repair_webhook`, open
  to push, cron and manual events. It takes no image filter: Woodpecker
  then gives it only to plugins, and `report-failure` is a plain step. A new
  task means a new URL in that secret (see the `t3-setup` skill).
- The task runs once per event, cron and commit, so a pipeline that fails
  again on the same commit, such as a rerun, starts no second repair.

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
