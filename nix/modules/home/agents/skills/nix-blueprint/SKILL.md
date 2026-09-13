---
name: nix-blueprint
description: How Wenxuan's flakes are laid out when they use numtide/blueprint - the folder-to-output mapping for hosts, modules, packages, devshells, checks, lib, and templates, plus the arguments each file receives. Read before adding, moving, or wiring a file in a blueprint flake, or when looking for where an output comes from.
---

# Blueprint Flakes

Most of my projects configure their flake with
[`numtide/blueprint`](https://github.com/numtide/blueprint). Blueprint derives
flake outputs from a folder structure instead of explicit output plumbing, so
adding a package, host, devshell, or module is normally a new file in the right
place and nothing else. Editing `flake.nix` to register an output is almost
always wrong.

The prefix is usually `nix/`, so the paths below are relative to that prefix
(e.g. `nix/hosts/<hostname>/configuration.nix`).

## Template to setup new projects

When setup a new project, use `nix flake init -t github:numtide/blueprint#treefmt-and-git-hooks`.

## Folder to output mapping

| Path                                                                 | Output                                                                            |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `flake.nix`                                                          | the flake itself; holds only inputs and blueprint config                          |
| `package.nix`                                                        | `packages.<system>.default`                                                       |
| `packages/<pname>(.nix\|/default.nix)`                               | `packages.<system>.<pname>` and `checks.<system>.pkgs-<pname>`                    |
| `formatter.nix`                                                      | `formatter.<system>`                                                              |
| `devshell.nix`                                                       | `devShells.<system>.default`                                                      |
| `devshells/<name>(.nix\|.toml)`                                      | `devShells.<system>.<name>`                                                       |
| `checks/<pname>(.nix\|/default.nix)`                                 | `checks.<system>.<pname>`                                                         |
| `hosts/<hostname>/configuration.nix`                                 | `nixosConfigurations.<hostname>`                                                  |
| `hosts/<hostname>/darwin-configuration.nix`                          | `darwinConfigurations.<hostname>`                                                 |
| `hosts/<hostname>/system-configuration.nix`                          | `systemConfigs.<hostname>` (system-manager)                                       |
| `hosts/<hostname>/rpi-configuration.nix`                             | `nixosConfigurations.<hostname>` (nixos-raspberrypi)                              |
| `hosts/<hostname>/default.nix`                                       | escape hatch returning `{ class; value; }`, takes precedence over the files above |
| `hosts/<hostname>/users/(<user>.nix\|<user>/home-configuration.nix)` | Home Manager user, standalone as `<user>@<hostname>`                              |
| `lib/default.nix`                                                    | `lib`                                                                             |
| `modules/<type>/(<name>\|<name>.nix)`                                | `modules.<type>.<name>`                                                           |
| `templates/<name>/`                                                  | `templates.<name>`                                                                |

Hosts also produce a `checks.<system>.(nixos\|darwin)-<hostname>` holding the
system closure, so `nix flake check` builds every machine.

`modules/<type>` maps the three well-known types to their conventional
outputs: `darwin` → `darwinModules.<name>`, `home` → `homeModules.<name>`,
`nixos` → `nixosModules.<name>`. Any other type name is allowed and lands only
under `modules.<type>.<name>`.

## Arguments each file receives

Per-system files (packages, devshells, checks, formatter) get:

- `pkgs` — nixpkgs instance configured by the flake
- `system` — the current system attribute
- `inputs` — the flake inputs
- `flake` — shorthand for `inputs.self`
- `perSystem` — every input's packages filtered to `system`, e.g.
  `perSystem.nixos-anywhere.default`; the flake's own packages are
  `perSystem.self.<pname>`
- `pname` — additionally passed to packages and checks

Host files get `inputs`, `flake`, `hostName`, and `perSystem`. User files get
`inputs`, `flake`, `perSystem`, plus Home Manager's own module arguments such
as `osConfig`. `lib/default.nix` gets `{ flake, inputs }`.

A module under `modules/` may be wrapped in a function taking `flake` and/or
`inputs`; blueprint calls it before exposing the output, which lets the module
refer to the flake that defines it rather than the one consuming it.

## Working in a blueprint flake

- To add something, create the file at the mapped path. Do not add an output
  to `flake.nix`.
- Nix only sees files tracked by git, so `git add` a new file before
  evaluating.
- Files must exist for blueprint to discover them; a host with only a `users/`
  tree becomes standalone `homeConfigurations` and no system configuration.
- If `home-manager` is an input, hosts with users import the Home Manager
  module automatically, with `useGlobalPkgs` and `useUserPackages` defaulted to
  true. Setting `nixpkgs.config` in a system module then conflicts with the
  injected `nixpkgs.pkgs`.
- Packages consumed as an overlay should go through the emitted
  `mkPackagesFor` so they build against the caller's nixpkgs.

Full reference:
https://numtide.github.io/blueprint/main/getting-started/folder_structure/
