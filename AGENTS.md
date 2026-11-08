Dotfiles is my personal system definition and configs managed by Nix.
The repo contains NixOS, nix-darwin, and Home Manager configs.

## Layout

- `/hosts` - Blueprint host definitions
- `/modules/hosts` - semantic system setting groups shared by NixOS and Darwin
- `/modules/caps` - system capability preset modules
- `/modules/home` - semantic Home Manager software groups
- `/modules/home/caps` - Home Manager capability preset modules
- `/overlays` - nixpkgs overlays
- `/packages` - software this repo pins from upstream, skill repositories
  agents take skills from included

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
`system`, `hostName`, `caps`, and optional extra `modules`. The helpers
import the selected system cap presets, expose host metadata as
`config.dotfiles.host.*`, set `nixpkgs.hostPlatform`, apply
`flake.lib.commonOverlays` (plus WSL's under `wsl = true`), and wire the
semantic system feature aggregator. Caps assign no overlays; a platform that
needs one applies it itself. `darwinHost` additionally
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

## Agents

`modules/home/agents` configures Claude Code, Codex, OpenCode, and Muse Code,
each in a module of its own that declares its entry in
`dotfiles.agents.harnesses`: package, instructions file, skill root, and the
model picker agent-settings runs for it. `harnesses.nix` renders every entry
the same way. They take what they share from options, never from each other:

- `dotfiles.llmGateways` (`modules/home/llm-gateways`): the model gateways,
  CLIProxyAPI and magpie, and `routes`, how agents reach each: homes with a
  [tailnet relay](#tailnet-relay) reach their tailnet origins, others the
  public ones (`publicRoutes`).
- `dotfiles.cloudflareAccess.serviceToken` (`modules/home/cloudflare-access`):
  the Cloudflare Access service token in front of the gateways, SearXNG, the
  NAS and zepbound. A consumer sets `enable` in its own gate and reads
  `idPath` and `secretPath`.
- `dotfiles.agents.launcher`: the git config and shell lines every launcher
  runs before its agent.
- `dotfiles.agents.mcp.servers`: MCP servers, `url` for a remote one and
  `command` for a local one. A feature adds its own server, and each agent
  takes the set in its config's shape from `dotfiles.agents.mcp.rendered`:
  the `browser` group adds Firefox DevTools' for its automation browser
  (`dotfiles.browser.firefox.automation.mcp`).
- `dotfiles.agents.skills`: the skills every agent sees (below).

Every agent reads `global-rules.md`, linked into its own config directory
(`rules.file`), with its own `rules.extraText` after it.

`modules/home/agentic-tooling` (`dotfiles.agenticTooling`) holds the programs
agents drive: REA, the video toolkit, formal verification, iPhone Use, Spark,
transcribe, wechat, and the tldraw whiteboard. Each adds its own skills and MCP
servers to the options above, and `modules/home/agents` never names one.

`checks/t3-tailnet`, `checks/t3-policy` and `checks/agent-skills` import
plain functions beside the modules (`modules/home/t3code/services.nix`,
`modules/home/t3code/policy-command.nix`, `skill-tree/build.nix`, and each
feature's `skills.nix`) so that they evaluate no home; those files take no
module arguments.

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
  `~/.local/share/agents/docs/<name>`. They are not skills; a package's
  skills read this way are ignored as skills.

Every deviation from a package's skill carries a reason: `override` requires
one, and a `local` skill that stands in for one a tool would install itself
sets one. Each feature declares its skills in a `skills.nix` beside its
module: a `dotfiles.agents.skills` value, from a function of
`{ pkgs, perSystem, flake, ... }`. The module adds it in the same gate as the CLI it
installs, and `checks/agent-skills` builds every `skills.nix` under
`modules/home` together, so a new feature needs no change there beyond the
list of skill names.

| Skill                                       | Source                     | Taken                                                 |
| ------------------------------------------- | -------------------------- | ----------------------------------------------------- |
| `modules/home/agents/skills/*`              | local                      | ours                                                  |
| every skill wxstack publishes               | `wxstack`                  | ours, published in whexy/wxstack                      |
| `sol-loop`                                  | `tstack`                   | picked from t3dotgg/tstack                            |
| `ketchup`, `bro`                            | `pstack`                   | picked from cursor/plugins' pstack                    |
| `statechart`, `*-formal-verification-skill` | `formal-verification`      | picked from pstack, with TLC for statechart           |
| `transcribe`, `wechat`                      | `transcribe`, `wechat-cli` | as shipped                                            |
| `video-edit`, `broll`                       | local, video feature       | ours; they drive several tools                        |
| `draw`                                      | local, tldraw feature      | ours; only where the whiteboard is reachable          |
| `reverse-engineer-anything`, `iphone-use`   | `rea-agents`, `iphone-use` | as shipped                                            |
| `iphone-use-setup`                          | `iphone-use`               | replaced by `agentic-tooling/iphone/iphone-use-setup` |
| `cf-cli`                                    | `cf`                       | patched by `tooling/cloudflare/cf-cli-skill.patch`    |
| `asc`, `spark`                              | local, with a reason       | the tools generate theirs at runtime                  |
| HyperFrames' skills, ManimGX's skill        | `hyperframes`, `manimgx`   | ignored; `broll` reads them by path as `docs`         |

Our packages of third-party tools copy every skill upstream publishes into
`share/skills`, and leave upstream's own copy where its code reads it. Each
one agents do not see is ignored with a reason, so a skill an upstream bump
adds or drops fails `checks/agent-skills` until it is accounted for. cf's
npm tarball ships no skill, so cf takes its own, `cf-cli`, from Cloudflare's
separate skills repository and none of that repository's product guides.

`skill-tree/build.nix` assembles the tree in one derivation. It fails on a listed
package without skills, two sources for one name, an override no package
provides, a patch that does not apply, a `docs` tree that reads a skill agents
see, and a `SKILL.md` whose frontmatter `name` is not its directory or whose
`description` is empty.

`checks/agent-skills` builds every skill in the repo at once and compares the
exposed names with the list written in it, plus what the skill repositories
build. The nightly update builds it for each package that ships skills, so an
upstream bump that breaks a patch holds back only that package. Changing
which skills agents see, other than a repository's, means changing that list.

```sh
nix build .#checks.x86_64-linux.agent-skills
```

### Skill repositories

A repository published for `npx skills` is a package, `packages/<name>`,
that calls `flake.lib.skillRepo`:

- `default.nix` declares it: `owner`, `repo`, and `skills`, the names to
  take as `npx skills add --skill` takes them. Without `skills`, every
  skill the repository publishes.
- `sources.json` pins it: `version`, `rev` and `hash`. `nix run .#update --
<name>` writes it, the first time and whenever the default branch moves,
  with the commit date as `0-unstable-<date>`. A second package from the
  same repository reads the first's pin with no updater of its own, and the
  first builds it through `alsoBuild` (formal-verification and pstack).

`flake.lib.skillRepo` builds what the `skills` CLI installs from the pinned
source, at `share/skills`, so agents see exactly what `npx skills add` gives
and nothing is vendored. A pick the repository lacks fails the build, and so
does an unpinned repository, so each new one is pinned before the next is
added. `modules/home/agents/skills.nix` lists the repositories every agent
gets, and `nix build .#<name>` shows one.

Skills anyone could use live in [whexy/wxstack](https://github.com/whexy/wxstack),
`packages/wxstack` here, which also installs with `npx skills add whexy/wxstack`
and as a Claude Code plugin marketplace. Skills that name our hosts,
credentials or infrastructure stay in `modules/home/agents/skills/`. Moving
one to wxstack deletes the local copy in the same change: the tree fails on
two sources for one name.

## Secrets

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
agenix -e openai-api-key.age -i ~/.ssh/agenix_ed25519
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
rotate the secret too.

## Auto-upgrade

Hosts with `dotfiles.system.autoUpgrade` (or the home's
`dotfiles.autoUpgrade`) run `dotfiles-upgraded`, which switches them to each
master commit that passes CI. CI's last passing step on a master push,
`announce`, signs the commit and publishes it to the ntfy topic in
`flake.lib.rollout`, on the cluster's tailnet relay. Daemons subscribe and
switch at once, and poll GitHub only every 6 hours while the stream is up
(every 10 minutes while it is down), so hosts behind one NAT stay within
GitHub's unauthenticated rate limit. b3srv0, off the tailnet, polls only.

- Woodpecker secrets, push events only: `rollout_signing_key` (the ed25519
  seed whose public key is `flake.lib.rollout.publicKey`) and
  `ntfy_rollout_token` (the relay's publish token, also sealed in
  clusters-work's `ntfy/ntfy`).
- `checks/bot-update-rollout` holds the step's place in the pipeline.
- `status.json` reports the stream under `notify`.

`packages/dotfiles-upgraded/README.md` holds the design, the trust model, and
key rotation.

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
token, `secrets/cloudflare-api-token.age`
(`dotfiles.tooling.cloudflare.apiToken`).

- `cf`'s wrapper reads the token on each run and exports it, with the
  token's account (`CLOUDFLARE_ACCOUNT_ID`), to that `cf` process alone. No
  shell or agent environment holds it.
- A token the caller brings wins: one already in the environment, or one in
  the `.env` that `cf` reads from the current directory.
- While the secret is not decrypted, `cf` runs signed out and says so.

Inside a project that depends on `cf`, the global command hands off to the
project's npm-installed copy. On NixOS its prebuilt workerd (`cf dev`) runs
through nix-ld, which the `dev` cap enables.

### Provision the token

1. In the Cloudflare dashboard, under Manage Account → Account API Tokens,
   create a custom token for the account in `modules/home/tooling/cloudflare`.
   Grant only what agents should do; reading is enough to start:
   Account Settings Read, Zone Read, DNS Read, and Workers Scripts Read, on
   all zones in the account. Editing the token's permissions later keeps its
   value, so the secret does not change.
2. On mudd or sheridan, from `secrets/`, paste the token into the editor
   that opens:

   ```sh
   agenix -e cloudflare-api-token.age -i ~/.ssh/agenix_ed25519
   ```

3. Commit the file and switch. `cf auth whoami` then reports
   `"tokenValid": true`.

To rotate, roll the token in the dashboard and repeat step 2.

## AWS CLI

The `dev` and `dev-lite` caps install AWS CLI v2
(`dotfiles.tooling.aws.enable`). Its default profile uses `credential_process`
to read `secrets/aws-credentials.age` when credentials are needed: JSON with
`Version` set to `1`, `AccessKeyId`, and `SecretAccessKey`. No key is written
to `~/.aws/credentials` or the shell environment.

Verify access with `aws sts get-caller-identity --region us-east-1`. No default
region is set; pass `--region`, set `AWS_DEFAULT_REGION`, or declare
`programs.awscli.settings.default.region` in the home config. Existing AWS
environment credentials take precedence over the default profile's process.
To rotate, replace the key pair in the JSON, from `secrets/` on mudd or
sheridan:

```sh
agenix -e aws-credentials.age -i ~/.ssh/agenix_ed25519
```

## Kubernetes clusters

The `dev`, `dev-lite` and `sysadmin` caps give every process kubectl access to
the clusters in `dotfiles.tooling.kube.clusters`. Each cluster's kubeconfig is
`secrets/kube-<name>.age` and names its cluster, user and context `<name>`.

- Activation decrypts the secrets with the home's agenix identity and builds
  `~/.kube/config` (mode 0600), the file kubectl reads by default, from them
  alone. Entries other tools add there are dropped; point those tools at a
  file of their own.
- Switch clusters with `kubectx <name>`. Activation keeps the current context
  and the namespace `kubens` set on it.
- A cluster whose secret cannot be decrypted is left out with a warning; when
  none can be, the file stays as it was.

Verify with `kubectl config get-contexts`.

## T3 Code server

`modules/home/t3code` (`dotfiles.t3code`, on the `dev`, `dev-lite` and
`sysadmin` caps) installs T3 Code and runs its server where `server.enable`
is set. The server listens only on loopback, at port 3773. On tailnet hosts
(`dotfiles.t3code.server.tailnet.enable`, on by default wherever
`dotfiles.network.tailscale` is), Tailscale Serve also publishes it at
`https://<MagicDNS name>:35338`. Every server is published on the public
internet by its own tunnel (below).

Standalone homes have no `osConfig`, so a standalone host that runs the
server enables it, its tailnet route, and `dotfiles.tunnels.hostName` itself
(b3srv0, off the tailnet; proxmox, on it). Its user services start at boot
only with lingering (`dotfiles.linger`), which the server, tunnels, the
tailnet relay and the auto-upgrade daemon turn on for standalone Linux homes.

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

### The server package

Every host runs whexy/t3code's server, `packages/t3code-fork`: the
`t3-server` output of the `t3code-fork` flake input (x86_64-linux and
aarch64-darwin), its derivation unchanged, so hosts substitute the path the
fork's CI pushed to `whexy-t3code.cachix.org`, a substituter every host
trusts (`lib/nix-settings.nix`). The input does not follow our nixpkgs, which
would change that path. A standalone home adds the substituter in its own
`nix.conf`, which the daemon honours only for a user it trusts; a root home
always is.

`flake.nix` pins the input to a `self-hosted-nightly` commit, never to the
branch, which the fork rebases onto each upstream nightly. The fork's CI
starts the `pin-t3code-fork` step in `.woodpecker.yml` with that commit as
`T3CODE_FORK_REV`. It pins a commit only while it is the fork's head and its
server closure is in Cachix for both systems, and moves the companion pins in
the same commit: the preview browser comes from the server source of the
pinned commit itself, and `t3code-desktop-nightly`'s updater follows the
version that commit builds. No T3 pin moves on its own.

To pin by hand, lock with an empty fetcher cache:
`XDG_CACHE_HOME=$(mktemp -d) nix flake update t3code-fork`. Nix caches a
source's hash by commit alone, and a checkout of the fork at that commit
hashes differently from GitHub's tarball (the checkout has no directories
for `.repos`' submodule links), so a home that evaluated one locks a hash
CI rejects.

### Managed policy

No policy lives in this repository. Each host follows the policy at
`dotfiles.t3code.policy.url`, by default
`https://t3-policy.clusters.work/dotfiles.json`, which the policy editor
(`https://t3-policy.at-basking.ts.net/`, on the tailnet) publishes. The
server's wrapper runs `t3code-policy resolve` before each start, on Linux and
macOS alike:

- It fetches the policy, retrying for up to 30 s (a boot can start the server
  before the network), and checks it with the `t3` about to run.
- A valid policy replaces the last good copy in
  `~/.local/state/t3code-policy/policy.json`, which the server then loads.
  When the URL is unreachable, serves an invalid policy, or answers 404 or
  410 (state `stale-missing`), the server loads the last good copy, after
  checking it again.
- With no valid policy at all, the wrapper names a file that cannot exist,
  which T3 reads as no policy. It never leaves the variable unset: T3 would
  then look for the machine's own policy.
- Each start writes `status.json` beside it and logs one
  `t3code-policy: state=...` line (the journal, or `~/Library/Logs/t3code.log`).
  A change of state posts to the alert webhook, which reaches WeChat.

The server reads its policy only at startup. Every 2 minutes,
`t3code-policy update` (the `t3code-policy-update` systemd timer, or launchd
agent on macOS) asks the URL for anything but the applied policy's sha256
(`If-None-Match`). When a running server's policy changed and the new one
passes the check, it restarts the server at once, and the wrapper applies it;
the server resumes interrupted turns. It never starts a stopped server, even
one stopped while it fetched: it checks again, and on Linux restarts with
`try-restart`.

- An unreachable URL or a server error restarts nothing and alerts nothing.
- An invalid policy restarts nothing; the state turns `stale-invalid`, which
  alerts once, and back to `current` when the URL serves the applied policy
  again. The same invalid bytes are not checked again.
- A 404 or 410 restarts nothing either; the state turns `stale-missing`,
  which alerts once, and back the same way.
- A start that still applies another policy after a restart for this one gets
  no second restart for the same sha within the hour.
- A lock keeps it from overlapping itself or a start. Every step is bounded,
  well below the 60 s a start waits for the lock; a start that still cannot
  take it loads the last good copy and writes nothing. It records each run under
  `update` in `status.json`, and logs a `t3code-policy: update=...` line when
  the result changes (the journal, or `~/Library/Logs/t3code-policy.log`).

`t3code-policy status` shows what the last start decided, the last update
check, and what the running server loaded. The last good copy is
user-writable, so an agent could replace it with another valid policy; the
check on every start keeps it to valid ones. `checks/t3-policy` runs the
command against a fixture server.

### Gateway models for Claude

T3's Claude model picker also lists every model the selected gateway serves.
The gateway entries of `claude-select` set
`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`, so Claude Code fetches the
gateway's model list, caches it in `~/.claude/cache/gateway-models.json`, and
reports it at initialize; T3 adds each model its own catalog does not know. The
same list appears in Claude Code's `/model`. With the claude.ai login selected,
the picker lists only Claude's own models.

CLIProxyAPI reports its models under encoded IDs (`claude-fable-5-dd-` and the
original ID reversed), which it routes back to the model, so thread metadata
shows those slugs. Every reported model offers the same effort levels, Low to
Max.

A new gateway model shows up from the second Claude session after it is
served: the first one refreshes the cache. Activation brings an existing
selection's gateway variables up to date, so the flag reaches hosts without
running `claude-select` again.

### Desktop app

The `gui` cap installs the T3 Code desktop app
(`dotfiles.t3code.desktop.enable`). On Linux it is
`t3code-desktop-nightly`, at the upstream nightly the pinned server builds,
with its own updater off. On macOS, activation installs
`/Applications/T3 Code (Nightly).app` at that nightly only when it is
missing, and the app updates itself from then on.

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

sheridan runs it (`dotfiles.agenticTooling.spark.server.enable`) as the `spark-mcp`
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

`dotfiles.agenticTooling.video.studio` (on the `dev` cap, and wherever `video`
is) registers SimpleStudio's MCP server,
`https://studio-mcp.clusters.work/mcp`, with every agent. Its tools generate
video on the studio's GPU Workers, and the `broll` skill fills B-roll slots
with that footage.

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

`dotfiles.agenticTooling.iphoneUse` (golf, mudd, deimos, sheridan) gives every
agent iPhone Use's tools for the phones in
`modules/home/agentic-tooling/iphone/phones.nix`.

Each phone runs WebDriverAgent on its own: it is launched as an installed app,
not by xcodebuild, so it keeps serving after the launcher exits and with no
computer attached. It listens only on the phone's Tailscale address
(`USE_IP`), and it has no authentication, so the tailnet ACL is the only gate:
whoever reaches port 8100 controls the unlocked phone. Its screen stream on
port 9100 ignores `USE_IP` and stays open on every network the phone joins.

Agents reach a phone through `iphone-use-select`, an MCP proxy in front of
iPhone Use:

- A session starts with no phone; the agent asks the user which one to use.
- The proxy forwards two loopback ports to that phone, because iPhone Use talks
  only to loopback: one to the runner (8100), and one to its screen stream
  (9100, `IPHONE_USE_MJPEG_URL`).
- iPhone Use's xcodebuild setup tools are hidden.
- Two agents on one phone end each other's sessions, because WebDriverAgent
  keeps only one.

iPhone Use's live preview, the MCP app that `pua_ready` and `pua_screen` show,
reads that screen stream with curl (`packages/iphone-use/mjpeg-relay.patch`);
upstream captures it over USB, which no host here does. It needs the tailnet to
reach the phone on port 9100.

- Before the user enters a password or uses Face ID, the agent pauses the
  preview. The pause is in the host's own state file, so a panel open on
  another host keeps streaming the phone's screen.
- `checks/iphone-preview` model-checks the preview's stream around a pause,
  and so does every iphone-use bump.
  The `verify-iphone-preview` project skill says what it covers.

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
the single place these names are defined). A feature adds its tunnel to
`dotfiles.tunnels.services` by `service` name and loopback port, and
`modules/home/tunnels` derives the tunnel, `<service>-<host>`, and the public
name, and runs each as a user service to that port, so traffic never passes
through the cluster. The host is `dotfiles.tunnels.hostName`, which a
standalone home sets itself.

No host is set up by hand. Every host decrypts the same `cloudflared-cert`
secret, the cert from one `cloudflared tunnel login` for the zone. On start a
tunnel service creates its tunnel (or recovers its credentials into
`~/.local/state/<service name>/` when the tunnel already exists), points the
DNS name at it, and runs it. The cert can create tunnels and edit every DNS
record in the zone, so only homes that run a tunnel can decrypt it (see
[Secrets](#secrets)).

## Tailnet relay

`dotfiles.tailnetRelay` (`modules/home/tailnet-relay`, `packages/tailnet-relay`)
puts a home that runs no Tailscale daemon, such as the shared servers mars and
venus, on the tailnet as a userspace (tsnet) node, `<hostName>` tagged
`tag:tailnet-relay`, without root. Each forward relays plain HTTP from a
loopback port to a tailnet HTTPS origin, opening the TLS itself. A feature adds
its forward where the relay is enabled:

- `dotfiles.llmGateways.relay`: Claude Code and Codex reach CLIProxyAPI and
  magpie at their tailnet origins, with no Cloudflare Access. Muse Code stays
  on the public origin, which alone rewrites `/muse-code/models`, and so do
  OpenCode and its search.
- Atuin syncs with `atuin.at-basking.ts.net`.
- The `wechat` CLI reaches the WeChat relay.
- `dotfiles-upgraded` subscribes to CI's announcements, with no
  `tailnet-relay-check`: they are signed, so whoever holds the port can only
  withhold them.
- Agents register the tldraw MCP server.

For other protocols the relay also runs a SOCKS5 proxy
(`dotfiles.tailnetRelay.proxy`, `127.0.0.1:47300`) to any tailnet address the
tag reaches, by MagicDNS name or address, TCP only:

- kubectl reaches the clusters: activation sets each cluster's `proxy-url` in
  `~/.kube/config`.
- ssh reaches the flake hosts by their bare names (except mars and venus) and
  any `*.at-basking.ts.net` host, through the `tailnet-relay-connect`
  `ProxyCommand` (`dotfiles.tailnetRelay.connect`).

Every user on the host can connect to a loopback port, and any user can bind
one the relay does not hold, so the check runs in both directions:

- The relay admits only connections whose client socket the kernel
  (sock_diag) reports as its own user's, and closes the rest before reading
  them. Anything running as that user is trusted, including a forwarder other
  users can reach.
- systemd user sockets hold the ports across relay restarts, and every client
  runs `tailnet-relay-check` (`dotfiles.tailnetRelay.checker`) before it
  connects, so another user who took a port gets nothing: agent-settings
  before it sends a gateway key, every agent launcher for the MCP servers,
  the `atuin` and `wechat` wrappers, and `tailnet-relay-connect`, since ssh
  trusts a new host's key on first use. kubectl runs no check: it verifies
  the API server against the kubeconfig's CA. While the relay is down, agents and
  `wechat` refuse to start, and Atuin keeps its history locally with sync off;
  none of them fall back to a public origin.
- Root on the host can take the node's identity from
  `~/.local/state/tailnet-relay` and reach whatever the tailnet policy grants
  the tag.

To add a home:

1. Once per tailnet, in the Tailscale admin console: add
   `"tag:tailnet-relay": ["autogroup:admin"]` to `tagOwners` and the grants
   `{ "src": ["tag:tailnet-relay"], "dst": ["tag:services"], "ip": ["tcp:443", "tcp:6443"] }`
   and `{ "src": ["tag:tailnet-relay"], "dst": ["whexy@github"], "ip": ["tcp:22"] }`.
   Nodes and ingress proxies share `tag:services`, so the relay reaches every
   tailnet UI on 443 and the Kubernetes API on 6443; the second grant is ssh
   to the owner's machines. Create an OAuth client that writes auth keys for the
   tag; its secret is `secrets/tailnet-relay-oauth.age`.
2. Add the home to that secret's recipients and rekey (see
   [Secrets](#secrets)).
3. Set `dotfiles.tailnetRelay = { enable = true; hostName = "<host>-relay"; };`
   and switch. On first start the node mints its own preauthorized,
   non-ephemeral key from the secret, and needs it again only if its state is
   lost.

`journalctl --user -u tailnet-relay` then shows
`tailnet: up as <hostName>.at-basking.ts.net.`

## Package updates

A package that fetches an upstream release declares how it is updated, as
data in `passthru.updater`, built with `flake.lib.updater` (`lib/updater.nix`,
which rejects a missing or unknown field at evaluation). A package that stays
frozen sets `passthru.updater = null;` with a comment saying why. Updatable
packages set `meta.changelog`, which their update commits link to.

The kinds, cheapest first:

- `nix-update`: runs `nix-update --flake <name>` with the package's `args`.
  Pins stay inline.
- `github-branch`: the head of a GitHub repository's default branch, pinned
  in `sources.json` as `rev`, `hash`, and the commit date as `version`.
- `npm`: an npm registry tarball. Bumps it with nix-update, regenerates the
  vendored package-lock.json from package.json after `lockfileFilter`, the
  jq filter the package's `postPatch` also applies (`flake.lib.npmTarball`
  sets both up), and re-pins `npmDepsHash`.
  `prebuilds` names dependencies whose install script downloads a prebuilt
  archive (`urlTemplate`, `platforms`); their pins in `sources.json` follow
  each dependency's version in the lockfile, and the package hands the
  archive to the install script.
- `platform-binaries`: one prebuilt archive per platform, from
  `versionSource`, `urlTemplate` and `platforms`; downloads each to hash it.
- `manifest-checksums`: per-platform binaries whose hashes the vendor's
  manifest lists, so nothing is downloaded.
- `script`: the `main()` of the package's own `update.py`, written with the
  `updater` library in `packages/update`; it reads its `settings` from the
  config, and an `UpdateError` it raises fails the package. packages/update's
  lint, typecheck and tests cover every `update.py`.

`github-branch` and the last three write `sources.json`, which the package
reads with `lib.importJSON`; `flake.lib.platformBinary` fetches a per-platform
pin from it with the `urlTemplate` and `platforms` the updater gets. Any kind can also take `subpackages` (passthru fetchers
whose hash follows the version), `followBranch` (passthru git fetchers that
move to their default branch's head with the package), `alsoBuild` (packages
that read this one's pins, or attributes such as `iphone-use.tests.preview`)
and `allowDowngrade`.

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

The nightly `update` step in `.woodpecker.yml` (`ci/update.sh`) runs
`nix flake update`, then `nix run .#update -- --commit`, which commits each
package as `chore(<name>): <old> -> <new>`, and pushes after the shared check
(`ci/check.sh`). Both lanes push through `push_master` in `ci/lib.sh`;
`checks/bot-update-rollout` runs them against stub `nix` and `git`.

## CI repair

When a pipeline on master fails (a push's check, the update lane, or the
t3code-fork pin lane), its last step, `report-failure`, posts the failure to a webhook
task on mudd's T3 Code server, "Repair a failed dotfiles pipeline". The task
starts an agent run in the Dotfiles project that reruns a transient failure,
or pushes a fix to master and reruns the update lane, so the packages it
reverted update.

- The task's webhook URL is the Woodpecker secret `t3_repair_webhook`, open
  to push, cron and manual events. It takes no image filter: Woodpecker
  then gives it only to plugins, and `report-failure` is a plain step. A new
  task means a new URL in that secret (see the `t3-setup` skill).
- The task runs once per event, cron, commit and pinned fork revision
  (`t3code_fork_rev` in the report), so a pipeline that fails again on the
  same commit, such as a rerun, starts no second repair.
- When the task does not accept the report, `report-failure` posts it to the
  alert webhook instead, which reaches WeChat.

## Commits

This repository keeps one branch, `master`, with linear history. Commit on
master and push it; rebase onto `origin/master` when the push is rejected.
Create no other branch, git worktree or pull request, and do not use the
`ship-pr` skill here: work left on a branch is easily forgotten and never
reaches master.

## Verification

(Before verification, remember to use `git add` to add new files, as flake
only see files tracked by git.)

Run `just verify` to evaluate every host and standalone home
(`ci/eval-all.sh`, which CI runs too) and build the updater check.
Run `just check` to run formatters and linters checklists.

## Dev environment

A `devShell` provides the formatters and linters on `PATH` (treefmt, nixfmt,
statix, nil, nixd, deadnix, stylua, prettier, shfmt, taplo).

Enter it with `nix develop`, or automatically via `direnv allow` (uses
`.envrc`). Entering the shell installs git pre-commit hooks (`git-hooks.nix`)
that run treefmt + statix + nil + deadnix before each commit; `just check`
runs them as `checks.<system>.pre-commit`. CI (`ci/check.sh`) builds every
check but the host closures, which it only evaluates (`ci/eval-all.sh`).

Formatter definitions live in `treefmt.nix` (single source of truth, shared by
`nix fmt`, the pre-commit hook, and the pre-commit check).
