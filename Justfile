# Dotfiles management commands

# List available commands
default:
    @just --list

# Update flake inputs (all or specific input)
update *INPUT:
    @if [ -z "{{INPUT}}" ]; then \
        echo "Updating all flake inputs..."; \
        nix flake update; \
    else \
        echo "Updating {{INPUT}}..."; \
        nix flake update {{INPUT}}; \
    fi

# Verify all flake outputs evaluate correctly
verify:
    @echo "Running flake checks..."
    nix flake check --extra-experimental-features 'nix-command flakes' --all-systems

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

# Build Proxmox VMA image for a NixOS configuration
# DISK_GB: disk size in GB (default: auto-sized based on closure)
build-proxmox CONFIG DISK_GB="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    
    DISK_ARG=""
    if [ "{{DISK_GB}}" != "auto" ]; then
        DISK_MB=$(({{DISK_GB}} * 1024))
        DISK_ARG="--disk-size $DISK_MB"
        echo "Building Proxmox VMA image for {{CONFIG}} ({{DISK_GB}}GB disk)..."
    else
        echo "Building Proxmox VMA image for {{CONFIG}} (auto-sized disk)..."
    fi
    
    nix run github:nix-community/nixos-generators -- \
        --flake .#{{CONFIG}} \
        --format proxmox \
        $DISK_ARG \
        -o result-proxmox
    
    VMA_FILE=$(find -L result-proxmox -name '*.vma.zst' -type f 2>/dev/null | head -1)
    
    echo ""
    echo "Build complete!"
    echo "Created: $VMA_FILE"
    echo ""
    echo "Upload to Proxmox and restore with: qmrestore <file>.vma.zst <vmid>"

# Build VirtualBox OVA image for the gui configuration
# NOTE: Large closures may fail due to LKL memory limits in cptofs.
#       If this happens, consider building on a NixOS system or using ISO install.
build-virtualbox:
    @echo "Building VirtualBox OVA image for gui..."
    nixos-rebuild build-image --flake .#gui --image-variant virtualbox
    @echo ""
    @echo "Build complete!"
    @echo "Created: result/nixos.ova"
    @echo ""
    @echo "Import into VirtualBox with: File -> Import Appliance -> select nixos.ova"
