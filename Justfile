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

# Verify primary configurations evaluate correctly (remote-dev, ord, mba, home)
verify:
    @echo "=== Verifying primary configurations ==="
    @echo "Evaluating remote-dev..."
    nix eval .#nixosConfigurations.remote-dev.config.system.build.toplevel.drvPath --show-trace
    @echo "OK - remote-dev"
    @echo "Evaluating ord..."
    nix eval .#nixosConfigurations.ord.config.system.build.toplevel.drvPath --show-trace
    @echo "OK - ord"
    @echo "Evaluating mba..."
    nix eval .#darwinConfigurations.mba.system.drvPath --show-trace
    @echo "OK - mba"
    @echo "Evaluating home (x86_64)..."
    nix eval .#homeConfigurations.home.activationPackage.drvPath --impure --show-trace
    @echo "OK - home (x86_64)"
    @echo "Evaluating home (aarch64)..."
    nix eval .#homeConfigurations.home-aarch64.activationPackage.drvPath --impure --show-trace
    @echo "OK - home (aarch64)"
    @echo "SUCCESS - All primary configurations evaluate correctly"

# Build WSL tarball for import (requires sudo)
build-wsl:
    @mkdir -p result/wsl
    @echo "Building WSL tarball..."
    nix build .#nixosConfigurations.wsl.config.system.build.tarballBuilder -o result/wsl/build
    @echo "Running tarball builder (requires sudo)..."
    cd result/wsl && sudo ../../result/wsl/build/bin/nixos-wsl-tarball-builder
    @echo "WSL tarball created: result/wsl/nixos.wsl"
    @echo "Import with: wsl --import NixOS <install-path> result/wsl/nixos.wsl"

# Build Proxmox VMA image for a NixOS configuration
# DISK_GB: disk size in GB (default: auto-sized based on closure)
build-proxmox CONFIG DISK_GB="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    
    mkdir -p result/proxmox
    
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
        -o result/proxmox
    
    VMA_FILE=$(find -L result/proxmox -name '*.vma.zst' -type f 2>/dev/null | head -1)
    
    echo ""
    echo "Build complete!"
    echo "Created: $VMA_FILE"
    echo ""
    echo "Upload to Proxmox and restore with: qmrestore <file>.vma.zst <vmid>"

# Build desktop VM image for specified backend and optional architecture
# Usage: just build-desktop utm [x86_64|aarch64]
#        just build-desktop vmware [x86_64|aarch64]
# If architecture is omitted, uses host architecture
build-desktop BACKEND ARCH="auto":
    @just build-desktop-{{BACKEND}} {{ARCH}}

# Build UTM qcow2 image for macOS virtualization
build-desktop-utm ARCH="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Detect architecture if not specified
    if [ "{{ARCH}}" = "auto" ]; then
        HOST_ARCH=$(uname -m)
        if [ "$HOST_ARCH" = "arm64" ]; then
            ARCH="aarch64"
        else
            ARCH="x86_64"
        fi
    else
        ARCH="{{ARCH}}"
    fi
    
    mkdir -p result/desktop

    echo "Building UTM qcow2 image for desktop ($ARCH)..."
    nix build \
        ".#nixosConfigurations.desktop-utm-${ARCH}.config.system.build.images.qemu-efi" \
        -o result/desktop/utm-${ARCH}

    QCOW2_FILE=$(find -L result/desktop/utm-${ARCH} -name '*.qcow2' -type f 2>/dev/null | head -1)

    echo ""
    echo "Build complete!"
    echo "Architecture: $ARCH"
    echo "Created: $QCOW2_FILE"
    echo ""
    echo "Import into UTM:"
    echo "  1. Create a new VM -> Emulate -> Linux"
    echo "  2. Skip boot ISO"
    echo "  3. In drive settings, import this qcow2 as the main disk"
    echo "  4. Set boot to UEFI in system settings"
    echo "  5. Set display to virtio-gpu-pci for Wayland support"
    echo "  6. Enable SPICE clipboard sharing"

# Build VMware VMDK image for desktop
build-desktop-vmware ARCH="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Detect architecture if not specified
    if [ "{{ARCH}}" = "auto" ]; then
        HOST_ARCH=$(uname -m)
        if [ "$HOST_ARCH" = "arm64" ]; then
            ARCH="aarch64"
        else
            ARCH="x86_64"
        fi
    else
        ARCH="{{ARCH}}"
    fi
    
    mkdir -p result/desktop

    echo "Building VMware VMDK image for desktop ($ARCH)..."
    nix build \
        ".#nixosConfigurations.desktop-vmware-${ARCH}.config.system.build.images.vmware" \
        -o result/desktop/vmware-${ARCH}

    VMDK_FILE=$(find -L result/desktop/vmware-${ARCH} -name '*.vmdk' -type f 2>/dev/null | head -1)

    echo ""
    echo "Build complete!"
    echo "Architecture: $ARCH"
    echo "Created: $VMDK_FILE"
    echo ""
    echo "Create a new VM in VMware and use this VMDK as the disk."
    echo "Recommended settings:"
    echo "  - Guest OS: Other Linux 6.x kernel 64-bit"
    echo "  - Enable 3D acceleration in Display settings"
    echo "  - Set clipboard/drag-drop to Bidirectional"

# Backward compatibility aliases
alias build-utm := build-desktop-utm
alias build-vmware := build-desktop-vmware
