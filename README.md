Reproducible chaos.

Supports macOS, NixOS, and whatever Linux you're running.

**Don't blindly apply this** unless you want to import my SSH keys and I'll have a free pass to your machine.

```shell
# Linux x86_64
nix run home-manager -- switch --flake github:whexy/dotfiles#linux

# Linux ARM
nix run home-manager -- switch --flake github:whexy/dotfiles#linux-aarch64

# macOS
sudo darwin-rebuild switch --flake github:whexy/dotfiles#macos

# NixOS remote dev box
nixos-install --flake github:whexy/dotfiles#remote-dev
```
