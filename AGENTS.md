Dotfiles is my personal system definition and configs managed by Nix.
The repo contains NixOS, nix-darwin, and Home Manager configs.

## Layout

- `/nix/hosts` - Blueprint host definitions
- `/nix/modules/hosts` - semantic system setting groups shared by NixOS and Darwin
- `/nix/modules/caps` - system capability preset modules
- `/nix/modules/home` - semantic Home Manager software groups
- `/nix/modules/home/caps` - Home Manager capability preset modules
- `/nix/overlays` - nixpkgs overlays

### System configs

System features are grouped semantically, like settings categories. A group
may contain related options for both platforms; platform-specific behavior
still belongs to that semantic group. For example, passwordless sudo,
1Password, fail2ban, and macOS biometric sudo all belong to `security`.

Each group follows this pattern:

- `nix/modules/hosts/<group>/default.nix` - declares `dotfiles.<group>.*`
  options (every option has a default)
- `nix/modules/hosts/<group>/nixos.nix` - NixOS config gated by those options
- `nix/modules/hosts/<group>/darwin.nix` - Darwin config gated by those options

`nix/modules/hosts/nixos.nix` and `darwin.nix` recursively aggregate the
matching files and exclude the other platform. Platforms, images, user setup,
and custom hardware metadata are option-driven groups under this same tree;
there are no separate `modules/nixos` or `modules/darwin` directories.

### Home configs

Home features represent software, grouped when related. Examples:

- `terminal` groups Ghostty, tmux, and zellij
- `editor` groups Neovim and Neovide
- `vcs` groups git and hunk
- `wm` groups niri and aerospace
- `keyboard` groups fcitx5 and Karabiner

A group's `default.nix` declares its `dotfiles.<group>.*` options and imports
its config files; config is gated with `lib.mkIf`. Standalone software can put
options and config together in its own `default.nix`. `homeModules.all`
aggregates all feature modules, while presets under `nix/modules/home/caps`
are imported selectively.

## Capabilities

Caps describe machine roles (`base`, `dev`, `dev-lite`, `gui`, `service`), but
**caps are not options or features**. They are preset modules:

- `nix/modules/caps/<cap>.nix` assigns system `dotfiles.*` options
- `nix/modules/home/caps/<cap>.nix` assigns Home Manager software options and
  cap-specific package lists

Feature option defaults have the lowest priority. Importing a cap assigns
normal-priority preset values. A host or user customizes the preset with
`lib.mkForce`, for example:

```nix
dotfiles.virtualization.docker.enable = lib.mkForce false;
```

A cap should only tune feature options; implementation remains in semantic
feature groups. Platform-specific options may be enabled by the same preset
and simply have no config on the other platform.

## Putting them together

Blueprint discovers hosts from `nix/hosts/<name>`. NixOS hosts use
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

Formatter definitions live in `nix/treefmt.nix` (single source of truth, shared by
`nix fmt`, the pre-commit hook, and the flake check).
