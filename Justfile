# Dotfiles management commands

# List available commands
default:
    @just --list

# Verify all flake outputs evaluate correctly
verify:
    @echo "Verifying NixOS configurations..."
    @nix eval .#nixosConfigurations.remote-dev --apply 'x: "ok"' && echo "  remote-dev: ok"
    @nix eval .#nixosConfigurations.wsl --apply 'x: "ok"' && echo "  wsl: ok"
    @echo "Verifying Darwin configurations..."
    @nix eval .#darwinConfigurations.mbp --apply 'x: "ok"' && echo "  mbp: ok"
    @nix eval .#darwinConfigurations.mini --apply 'x: "ok"' && echo "  mini: ok"
    @echo "Verifying Home Manager configurations..."
    @nix eval .#homeConfigurations.home --apply 'x: "ok"' && echo "  home: ok"
    @echo "Verifying packages..."
    @nix eval .#packages.x86_64-linux.portable-nvim --apply 'x: "ok"' && echo "  portable-nvim: ok"
    @echo "All configurations verified!"

# Build WSL tarball for import (requires sudo)
build-wsl:
    @echo "Building WSL tarball..."
    nix build .#nixosConfigurations.wsl.config.system.build.tarballBuilder
    @echo "Running tarball builder (requires sudo)..."
    sudo ./result/bin/nixos-wsl-tarball-builder
    @echo "WSL tarball created: nixos.wsl"
    @echo "Import with: wsl --import NixOS <install-path> nixos.wsl"

# Build portable neovim binary using nix-portable bundler
build-portable-nvim:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "Bundling portable-nvim with nix-portable (zstd-max compression)..."
    nix bundle --bundler github:DavHau/nix-portable#zstd-max -o bundle-nvim .#packages.x86_64-linux.portable-nvim
    
    echo "Creating standalone executable..."
    cp ./bundle-nvim/bin/nvim ./nvim
    chmod +w ./nvim
    
    echo ""
    echo "Build complete!"
    echo "Created: ./nvim (portable, self-contained executable)"
    echo ""
    echo "Distribute this single file. Users can run it on any x86_64 Linux system."
