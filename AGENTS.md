Dotfiles is my personal system definition and configs managed by Nix.
The repo contains NixOS, nix-darwin, and Home Manager configs.

## Layout

- `/nix/hosts` - Blueprint host definitions
- `/nix/modules/nixos` - NixOS modules, including capability and reusable platform modules
- `/nix/modules/darwin` - nix-darwin modules, including capability modules
- `/nix/modules/home` - Home Manager modules shared by integrated and standalone homes
- `/nix/overlays` - nixpkgs overlays

### System configs

System configs are operating-system settings, for example:

- locale, e.g., which timezone should the system use
- power settings, e.g., how long should sleep after idle
- some "heavy" system packages, e.g., whether to enable docker, openssh

System configs are platform-specific Blueprint modules:

- `nix/modules/nixos/{cap}.nix` - NixOS-specific settings
- `nix/modules/darwin/{cap}.nix` - Darwin-specific settings

### Home configs

Home configs are user space settings, for example:

- packages, e.g., enable zsh, neovim, ripgrep
- software settings, e.g., zshrc, neovim init.lua, tmux config

Home configs are cross-platform Blueprint modules exposed as
`homeModules.<name>`. They are shared between NixOS, Darwin, and standalone
Home Manager outputs.

## Capabilities

I have so many systems managed by nix, so I define "caps" to describe the
capability of a certain machine.

`base` cap:
very basic settings, all system should have them. For example, zsh.

`dev` cap:
machines used for development. dev setups like fancy NeoVim, LSPs, Linters,
Formatters, direnv, everything for better developer experience.

`gui` cap:
machines expected to have GUI environments. Enable GUI related setups,
like ghostty, browser, fonts.
Also included macOS-specific settings like dock, finder, Touch ID for sudo.

For example, a remote NixOS dev machine should enable base+dev.
My macOS machines enable base+dev+gui+macos.

## Putting them together

Blueprint discovers hosts from `nix/hosts/<name>`. NixOS hosts use
`configuration.nix`; Darwin hosts use `default.nix` so they can keep using the
Darwin-specific Home Manager input. Host-specific hardware lives beside the host
as `hardware.nix`; reusable VM/image/platform modules live in `nix/modules/nixos`.

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
