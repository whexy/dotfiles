Dotfiles is my personal system definition and configs managed by Nix.
The repo contains NixOS, nix-darwin, and Home Manager configs.

## Layout

- `/hardware` - hardware configs (NixOS and Darwin)
- `/system` - system configs (platform-specific per cap)
- `/home` - home manager configs
- `/users` - user account definitions
- `/overlays` - nixpkgs overlays

### System configs

System configs are operating-system settings, for example:

- locale, e.g., which timezone should the system use
- power settings, e.g., how long should sleep after idle
- some "heavy" system packages, e.g., whether to enable docker, openssh

System configs are platform-specific. For each cap, there are two files:
- `system/{cap}-nixos.nix` - NixOS-specific settings
- `system/{cap}-darwin.nix` - Darwin-specific settings

### Home configs

Home configs are user space settings, for example:

- packages, e.g., enable zsh, neovim, ripgrep
- software settings, e.g., zshrc, neovim init.lua, tmux config

Home configs are cross-platform and shared between NixOS and Darwin.

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

A special function `mkHost` is defined in `mkhost.nix` file.
This function takes:

- `system`: e.g., `x86_64-linux` or `aarch64-darwin`
- `hardware`: e.g., `qemu-x86_64` or `macos-laptop`
- `hostname`: the machine's hostname
- `username`: the primary user
- `caps`: list of capabilities to enable
- `darwin`: set to `true` for macOS systems

Example NixOS configuration:

```nix
nixosConfigurations = {
    remote-dev = mkHost {
        system = "x86_64-linux";
        hardware = "qemu-x86_64";
        hostname = "remote-dev";
        username = "whexy";
        caps = [ "base" "dev" ];
    };
};
```

Example Darwin configuration:

```nix
darwinConfigurations = {
    mbp = mkHost {
        system = "aarch64-darwin";
        hardware = "macos-laptop";
        hostname = "mbp";
        username = "whexy";
        darwin = true;
        caps = [ "base" "dev" "gui" "macos" ];
    };
};
```

## Verification

Run `just verify` to check all flake outputs evaluate correctly.
Before verification, remember to use `git add` to add modified code, as flake
only use staged files.
