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
    @mkdir -p result/wsl
    @echo "Building WSL tarball..."
    nix build .#nixosConfigurations.wsl.config.system.build.tarballBuilder -o result/wsl/build
    @echo "Running tarball builder (requires sudo)..."
    cd result/wsl && sudo ../../result/wsl/build/bin/nixos-wsl-tarball-builder
    @echo "WSL tarball created: result/wsl/nixos.wsl"
    @echo "Import with: wsl --import NixOS <install-path> result/wsl/nixos.wsl"

# Build portable neovim binary using nix-portable bundler
build-portable-nvim:
    #!/usr/bin/env bash
    set -euo pipefail
    
    mkdir -p result/portable-nvim
    
    echo "Bundling portable-nvim with nix-portable (zstd-max compression)..."
    nix bundle --bundler github:DavHau/nix-portable#zstd-max -o result/portable-nvim/bundle .#packages.x86_64-linux.portable-nvim
    
    echo "Creating standalone executable..."
    cp ./result/portable-nvim/bundle/bin/nvim ./result/portable-nvim/nvim
    chmod +w ./result/portable-nvim/nvim
    
    echo ""
    echo "Build complete!"
    echo "Created: result/portable-nvim/nvim (portable, self-contained executable)"
    echo ""
    echo "Distribute this single file. Users can run it on any x86_64 Linux system."

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

# Create a new nixos-anywhere target placeholder
# After this, add a corresponding entry in flake.nix nixosConfigurations
add-anywhere HOSTNAME:
    #!/usr/bin/env bash
    set -euo pipefail

    GENERATED="hardware/{{HOSTNAME}}-generated.nix"

    if [ -f "$GENERATED" ]; then
        echo "Placeholder already exists: $GENERATED"
        exit 0
    fi

    echo 'throw "Run: just deploy-anywhere {{HOSTNAME}} <ip>"' > "$GENERATED"
    git add "$GENERATED"

    echo "Created placeholder: $GENERATED"
    echo ""
    echo "Now add this to flake.nix nixosConfigurations:"
    echo ""
    echo '    {{HOSTNAME}} = mkHost {'
    echo '      system = "x86_64-linux";'
    echo '      hardware = "anywhere";'
    echo '      hostname = "{{HOSTNAME}}";'
    echo '      username = "whexy";'
    echo '      caps = [ "base" "service" ];'
    echo '    };'

# Deploy NixOS to a remote machine via nixos-anywhere
deploy-anywhere HOSTNAME IP:
    #!/usr/bin/env bash
    set -euo pipefail

    GENERATED="hardware/{{HOSTNAME}}-generated.nix"

    if [ ! -f "$GENERATED" ]; then
        echo "No placeholder found. Run first: just add-anywhere {{HOSTNAME}}"
        exit 1
    fi

    # Stage all files so flake can see them
    git add -A

    echo "Deploying {{HOSTNAME}} to {{IP}}..."
    nix run github:nix-community/nixos-anywhere -- \
        --generate-hardware-config nixos-generate-config "$GENERATED" \
        --flake ".#{{HOSTNAME}}" \
        --target-host "root@{{IP}}"

    echo ""
    echo "Deployment complete!"
    echo "Don't forget to commit the generated hardware config:"
    echo "  git add $GENERATED && git commit -m 'Add generated hardware config for {{HOSTNAME}}'"

# Backward compatibility aliases
alias build-utm := build-desktop-utm
alias build-vmware := build-desktop-vmware
