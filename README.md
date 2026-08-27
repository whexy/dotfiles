<div align="center">

<picture> <img alt="NixOS logo"
    src="https://raw.githubusercontent.com/NixOS/nixos-artwork/refs/heads/master/logo/nix-snowflake-colours.svg"
    width="80"> </picture>

# Dotfiles

[![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=for-the-badge&logo=nixos&logoColor=white)](https://nixos.org)
[![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://nix-darwin.com)
[![Home
Manager](https://img.shields.io/badge/Home%20Manager-5277C3?style=for-the-badge&logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![Tailscale](https://img.shields.io/badge/Tailscale-000000?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com)

<picture> <img alt="macOS desktop"
    src="docs/dotfiles_macOS.png"
    width="700"> </picture>

</div>

My personal Nix configuration for all my machines: NixOS, Macs, WSL.

### Layout

The flake is built on [blueprint](https://github.com/numtide/blueprint), so
hosts and users are discovered from the directory layout. Custom host helpers
wire in caps, host metadata, platform packages, and Home Manager for each
integrated user.

### Capabilities and Features

Caps are preset modules that assign feature options. A host picks its caps and
then overrides individual options where needed.

Feature modules are semantic groups: `default.nix` declares the options,
`nixos.nix` / `darwin.nix` hold the platform-specific config.

### Secrets and Remote access

Secrets are age-encrypted with agenix and only decrypted on the hosts that need
them.

Tailscale on everything, so I can safely expose services in private network.

### Automation

Woodpecker CI evaluates configurations on every push and runs the pre-commit
checks (treefmt, statix, nil, deadnix).

Nightly, a GitHub App bot updates `flake.lock` when inputs drift.

Servers and standalone Home Manager setups auto-upgrade daily from the flake, so
the fleet stays near the same revision.
