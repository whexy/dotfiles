# 2. Human and agent profiles

Paths are relative to the repository root. All findings are [V]: read in
the modules, or evaluated from
`legacyPackages.x86_64-linux.homeConfigurations."user@sandbox"` and its built
`home-files`.

## Leaks in the current image

The image contains no plaintext secrets. It does carry a person's identity,
and it wires the agent into that person's infrastructure.

| Severity | Item                                                                                                                                                                                              | Source                                                                         |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| High     | `personal` MCP capability URL (no authentication) in `.claude.json`, `.codex/config.toml`, `.pi/agent/mcp.json` and `opencode.json`                                                               | `modules/home/agents/mcp.nix:49-57`                                            |
| High     | Agent configs reference agenix paths, and the image ships ciphertexts for 6 secrets (reachable from the activation package). Copying the age key in to "make it work" would expose all 15 secrets | `modules/home/agents/default.nix:246-260`, `caps/dev-lite.nix:41-42`           |
| Medium   | Git and jj identity, a forced SSH signing key, `.git_allowed_signers`, and the gh credential helper. Commits are authored as the owner, and signing fails, which teaches agents to bypass it      | `modules/home/vcs/git.nix:22-63,76-83`                                         |
| Medium   | `.ssh/config`: personal university hosts and usernames, `Host * ForwardAgent yes`, the 1Password agent socket, and the agent router                                                               | `modules/home/ssh/default.nix:47-83`, `ssh/agent-router.nix:14-27`             |
| Medium   | Tailnet name and Atuin `auto_sync`; wechat-relay default URL and skill                                                                                                                            | `shell/zsh-extras.nix:78-82`, `packages/wechat-cli/src/wechat_cli/relay.py:18` |
| Medium   | Tools that open paths out: `kubectl`, `cloudflared` (quick tunnels), `nmap`/`tcpdump`/`socat`, `t3-pair`, `wechat-cli`                                                                            | `tooling/cli.nix:141,147`, `tooling/network.nix`, `agents/default.nix:227`     |
| Medium   | `accept-flake-config = true` on a user-owned store with no daemon. Any flake the agent runs can add substituters and trusted keys, or set a `post-build-hook`                                     | `lib/nix-settings.nix:21`                                                      |
| Low      | Personal "About me" in agent instructions; the git-commit skill names hosts                                                                                                                       | `modules/home/agents/AGENTS.md:7-10`, `skills/git-commit/SKILL.md:50-53`       |
| Low      | Interactive clutter: p10k, oh-my-zsh, nushell, starship, tmux, htop/btop, motd, comma, podman, lazygit                                                                                            | `caps/base.nix:28-54`, `caps/dev-lite.nix:18-48`                               |

The sandbox also uses `lib.mkForce` to switch off seven editor options,
`ghTokenFlakes`, `gpg-agent` and `nix.gc`
(`hosts/sandbox/users/user/home-configuration.nix:27-45`). That much
overriding is the sign that `dev-lite` is the wrong base for an agent.

## Classification

| Group                                                                                                                                       | Keep for agents                                                          | Human only                                               | Needs rework                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------- | ------------------------------------------------------------ |
| `vcs`                                                                                                                                       | git, git-lfs, delta (non-interactive diff)                               | jj, lazygit                                              | identity, signing, credential helper are hardcoded           |
| `tooling.cli`                                                                                                                               | fd, ripgrep, jq, just, file, archivers, lsof, nix-output-monitor         | lazygit, ncdu, duf, dust, tldr, doordash-cli, caffeinate | age/agenix, kubectl, cloudflared, 1Password CLI (ops access) |
| `tooling.network`                                                                                                                           | dig, openssl                                                             | iperf3, mtr, traceroute                                  | nmap, tcpdump, socat (offensive in a sandbox)                |
| `tooling.debug`                                                                                                                             | strace, ltrace, rr (where allowed), valgrind                             | reptyr                                                   | bpftrace, perf (need caps the sandbox lacks)                 |
| `tooling.extras`                                                                                                                            | sqlite, watchexec, xh, yq                                                | yazi, magic-wormhole                                     | qemu, devenv (heavy)                                         |
| `editor.<lang>`                                                                                                                             | toolchains (python3+uv, compilers, formatters, linters)                  | Neovim, Neovide, LSP wiring                              | toolchains are tied to the editor option                     |
| `shell`                                                                                                                                     | plain zsh or bash, direnv (never auto-allowed)                           | p10k, oh-my-zsh, fzf-tab, nushell, starship, motd        | atuin (secret plus tailnet sync)                             |
| `terminal`, `monitors`, `wm`, `panel`, `desktop`, `clipboard`, `keyboard`, `launcher`, `streaming`, `browser` (except automation), `rclone` | none                                                                     | all                                                      | none                                                         |
| `ssh`                                                                                                                                       | none                                                                     | personal hosts, agent router                             | none                                                         |
| `nix`                                                                                                                                       | caches (pinned), registry pin                                            | nh, comma/nix-index, auto-upgrade                        | ghTokenFlakes                                                |
| `agents`                                                                                                                                    | harness packages and skills (for in-sandbox CLI agents), in sandbox mode | personal MCP, wechat, notify, t3code, cmux               | credential source, proxy accounts                            |

## Proposed module layout

This follows the repository conventions (AGENTS.md): caps are presets, feature
groups own the options, hosts override with `lib.mkForce`, and options have
defaults.

### Caps

```
modules/home/caps/
  core.nix     NEW   stateVersion, nix caches/registry, minimal shell; shared by all
  base.nix     CHG   imports nothing new; becomes "core + human terminal defaults"
                     (htop/btop/tmux/motd/neovim, openssh, mosh, podman, nix.gc)
  dev-lite.nix       unchanged for humans
  dev.nix            unchanged
  agent.nix    NEW   preset for autonomous agents (replaces base + dev-lite in sandboxes)
```

A new cap file needs no wiring: `homeCapsModules` resolves caps by name
(`lib/default.nix:28`). The sandbox home then lists `[ "core" "agent" ]`, and
human homes keep `[ "base" "dev" … ]`. Moving `nix.gc` and the terminal
defaults out of `core` changes no existing host, because `base` keeps them.

`caps/agent.nix` would set:

```nix
dotfiles = {
  vcs.git = {
    enable = true;
    identity = { name = "whexy-agent[bot]"; email = "<id>+whexy-agent[bot]@users.noreply.github.com"; };
    signing.enable = false;          # GitHub signs API-created commits
    credentialHelper = "none";       # or "broker" in stage 3
  };
  tooling = { core.enable = true; build.enable = true; debug.enable = true; };
  lang = { python.enable = true; javascript.enable = true; nix.enable = true; shell.enable = true; };
  nix.flakeConfig.accept = false;
  agents = {
    enable = true;                   # only if CLI agents run inside the sandbox
    sandbox.enable = true;
    credentials.source = "none";
    mcp.personal.enable = false;
    notify.enable = false;
    instructions.aboutMe = false;
  };
};
```

### Options to add or change

| Option                                                                                                         | Group file                        | Purpose                                                                                                     |
| -------------------------------------------------------------------------------------------------------------- | --------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `dotfiles.vcs.git.identity.{name,email}`                                                                       | `modules/home/vcs/default.nix`    | Replaces the hardcoded identity (`git.nix:44-47,79-82`). Defaults keep today's values                       |
| `dotfiles.vcs.git.signing.{enable,key,allowedSigners}`                                                         | same                              | Replaces `git.nix:22-41`. Defaults keep today's behaviour                                                   |
| `dotfiles.vcs.git.credentialHelper` (`"gh" \| "broker" \| "none"`)                                             | same                              | `broker` uses a helper that asks the session-scoped Git proxy ([04](04-git-credentials.md))                 |
| `dotfiles.ssh.personalHosts.enable`, `dotfiles.ssh.forwardAgent`                                               | `modules/home/ssh/default.nix`    | Stops `ForwardAgent yes` on `*` and the personal hosts from reaching agents                                 |
| `dotfiles.shell.atuin.enable`, `dotfiles.shell.direnv.enable`                                                  | `modules/home/shell/default.nix`  | Split out of `devExtras`                                                                                    |
| `dotfiles.tooling.{core,ops,personal,build}.enable`                                                            | `modules/home/tooling/`           | Split `cli` so agents get core without kubectl, cloudflared or doordash; `build` holds gcc, make, node, tsc |
| `dotfiles.lang.<lang>.enable`                                                                                  | NEW `modules/home/lang/`          | Toolchains without the editor; `editor.<lang>` keeps only the Neovim wiring and implies `lang.<lang>`       |
| `dotfiles.nix.flakeConfig.accept`                                                                              | `modules/home/nix/default.nix`    | `accept-flake-config`; `false` in the agent cap                                                             |
| `dotfiles.agents.sandbox.enable`                                                                               | `modules/home/agents/default.nix` | No `age.secrets`, services, activation-only features or t3code                                              |
| `dotfiles.agents.credentials.source` (`"agenix" \| "env" \| "none"`)                                           | same                              | How launchers get model credentials                                                                         |
| `dotfiles.agents.mcp.personal.enable`, `dotfiles.agents.notify.enable`, `dotfiles.agents.instructions.aboutMe` | same                              | Default on for humans, off in the agent cap                                                                 |

### System side

Nothing in this repository manages the Kubernetes cluster
(the cluster is referenced only in `.woodpecker.yml:1-11` and host comments).
The repository's deliverables to the cluster are:

- `packages/sandbox-image`: the image, built from the `agent` profile
- a pinned `/etc/nix/nix.conf` in the image: `substituters` and
  `trusted-public-keys` fixed, `accept-flake-config = false`, `sandbox = false`
- optionally `packages/sandbox-broker`, the credential broker as a Nix
  package, and a NixOS module for it if it runs on a host rather than in the
  cluster ([03](03-secrets.md), [04](04-git-credentials.md))

### Reproducibility notes

- The image is built entirely from `flake.lock`: the n8n daemon and workspace
  come from the pinned `n8n-sandbox-service` input, and packages from nixpkgs.
  Verified by building on 2026-09-25.
- The agent settings seeded at build time are deterministic JSON from store
  inputs.
- The image `tag` is `latest`. Deployments should reference the digest printed
  by `docker load`, or push with `skopeo copy` and record the digest in the
  cluster values.
