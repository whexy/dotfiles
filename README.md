<div align="center">

<picture>
  <img alt="NixOS logo" src="https://raw.githubusercontent.com/NixOS/nixos-artwork/refs/heads/master/logo/nix-snowflake-colours.svg" width="80">
</picture>

# Dotfiles

**Reproducible chaos across machines.**

<br>

</div>

> [!WARNING]
> **Don't blindly apply this** unless you want to import my SSH keys and I'll have a free pass to your machine.

## Quick Start

### Dotfiles-only

For x86_64 Linux:
```bash
home-manager switch --flake github:whexy/dotfiles#home --impure
```

For aarch64 Linux:
```bash
home-manager switch --flake github:whexy/dotfiles#home-aarch64 --impure
```

> **Note:** The `--impure` flag is required because this configuration reads your username and home directory path from environment variables (`$USER` and `$HOME`).

### macOS

```bash
sudo darwin-rebuild switch --flake github:whexy/dotfiles#mbp
```

### NixOS

```bash
sudo nixos-rebuild switch --flake github:whexy/dotfiles#remote-dev
```

### WSL

```bash
nix build github:whexy/dotfiles#nixosConfigurations.wsl.config.system.build.tarballBuilder
sudo ./result/bin/nixos-wsl-tarball-builder
```

