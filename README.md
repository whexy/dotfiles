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

### nixos-anywhere (deploy to any machine via SSH)

Install NixOS on any reachable machine using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere). The target must be accessible via SSH as root (or a user with passwordless sudo).

**1. Create a placeholder for the new host:**

```bash
just add-anywhere myserver
```

**2. Add the host entry to `flake.nix`** under `nixosConfigurations`:

```nix
myserver = mkHost {
  system = "x86_64-linux";
  hardware = "anywhere";
  hostname = "myserver";
  username = "whexy";
  caps = [ "base" "service" ];
};
```

**3. Deploy:**

```bash
just deploy-anywhere myserver 192.168.1.100
```

This will partition the disk via [disko](https://github.com/nix-community/disko), install NixOS, and generate a hardware config at `hardware/myserver-generated.nix`.

**4. Commit the generated hardware config:**

```bash
git add hardware/myserver-generated.nix
git commit -m "Add generated hardware config for myserver"
```

> **Note:** The default disk layout (`hardware/disko-config.nix`) uses `/dev/sda`. If the target disk is different (e.g. `/dev/nvme0n1`), override it in the host's flake entry or disko config. Run `lsblk` on the target to identify the correct disk.

