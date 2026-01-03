<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/NixOS/nixos-artwork/refs/heads/master/logo/nix-snowflake-colours.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/NixOS/nixos-artwork/refs/heads/master/logo/nix-snowflake.svg">
  <img alt="NixOS logo" src="https://raw.githubusercontent.com/NixOS/nixos-artwork/refs/heads/master/logo/nix-snowflake.svg" width="80">
</picture>

# Dotfiles

**Reproducible chaos across machines.**

<br>

</div>

> [!WARNING]
> **Don't blindly apply this** unless you want to import my SSH keys and I'll have a free pass to your machine.

## Quick Start

### Linux x86_64

```bash
nix run home-manager -- switch --flake github:whexy/dotfiles#linux --impure
```

### Linux ARM

```bash
nix run home-manager -- switch --flake github:whexy/dotfiles#linux-aarch64 --impure
```

### macOS

```bash
sudo darwin-rebuild switch --flake github:whexy/dotfiles#macos
```

### NixOS

```bash
nixos-install --flake github:whexy/dotfiles#remote-dev
```

