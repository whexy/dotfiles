# Build an encrypted Incus VM image.
# The passphrase is read without echo and is only copied into the isolated
# image-builder VM before LUKS formatting; it is not stored in the image.
build-phobos:
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p result/phobos

    PASSPHRASE_FILE=$(mktemp)
    trap 'rm -f "$PASSPHRASE_FILE"' EXIT
    chmod 600 "$PASSPHRASE_FILE"

    read -r -s -p "LUKS passphrase: " PASSPHRASE
    echo
    read -r -s -p "Confirm LUKS passphrase: " CONFIRM
    echo

    if [ "$PASSPHRASE" != "$CONFIRM" ]; then
        echo "Passphrases do not match" >&2
        exit 1
    fi
    printf %s "$PASSPHRASE" > "$PASSPHRASE_FILE"
    unset PASSPHRASE CONFIRM

    echo "Building phobos Disko image script..."
    nix build \
        .#nixosConfigurations.phobos.config.system.build.diskoImagesScript \
        -o result/phobos/build

    rm -f result/phobos/phobos.qcow2 phobos.qcow2
    echo "Building encrypted qcow2 image (requires sudo)..."
    sudo result/phobos/build \
        --build-memory 4096 \
        --pre-format-files "$PASSPHRASE_FILE" /tmp/phobos-luks-passphrase
    sudo mv phobos.qcow2 result/phobos/phobos.qcow2
    sudo chown "$(id -u):$(id -g)" result/phobos/phobos.qcow2

    METADATA=$(nix build \
        .#nixosConfigurations.phobos.config.system.build.metadata \
        --no-link \
        --print-out-paths)
    METADATA_FILE=$(find "$METADATA/tarball" -name '*.tar.xz' -type f -print -quit)
    cp -L "$METADATA_FILE" result/phobos/incus-metadata.tar.xz

    echo ""
    echo "Build complete!"
    echo "Disk:     result/phobos/phobos.qcow2"
    echo "Metadata: result/phobos/incus-metadata.tar.xz"
    echo ""
    echo "Import on the Incus host:"
    echo "  incus image import --alias phobos-image result/phobos/incus-metadata.tar.xz result/phobos/phobos.qcow2"
    echo "  incus launch phobos-image phobos --vm -c security.secureboot=false"
    echo "  incus console phobos"

build-zoozve:
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p result/zoozve

    PASSPHRASE_FILE=$(mktemp)
    trap 'rm -f "$PASSPHRASE_FILE"' EXIT
    chmod 600 "$PASSPHRASE_FILE"

    read -r -s -p "LUKS passphrase: " PASSPHRASE
    echo
    read -r -s -p "Confirm LUKS passphrase: " CONFIRM
    echo

    if [ "$PASSPHRASE" != "$CONFIRM" ]; then
        echo "Passphrases do not match" >&2
        exit 1
    fi
    printf %s "$PASSPHRASE" > "$PASSPHRASE_FILE"
    unset PASSPHRASE CONFIRM

    echo "Building zoozve Disko image script..."
    nix build \
        .#nixosConfigurations.zoozve.config.system.build.diskoImagesScript \
        -o result/zoozve/build

    rm -f result/zoozve/zoozve.qcow2 zoozve.qcow2
    echo "Building encrypted qcow2 image (requires sudo)..."
    sudo result/zoozve/build \
        --build-memory 4096 \
        --pre-format-files "$PASSPHRASE_FILE" /tmp/zoozve-luks-passphrase
    sudo mv zoozve.qcow2 result/zoozve/zoozve.qcow2
    sudo chown "$(id -u):$(id -g)" result/zoozve/zoozve.qcow2

    METADATA=$(nix build \
        .#nixosConfigurations.zoozve.config.system.build.metadata \
        --no-link \
        --print-out-paths)
    METADATA_FILE=$(find "$METADATA/tarball" -name '*.tar.xz' -type f -print -quit)
    cp -L "$METADATA_FILE" result/zoozve/incus-metadata.tar.xz

    echo ""
    echo "Build complete!"
    echo "Disk:     result/zoozve/zoozve.qcow2"
    echo "Metadata: result/zoozve/incus-metadata.tar.xz"
    echo ""
    echo "Import on the Incus host:"
    echo "  incus image import --alias zoozve-image result/zoozve/incus-metadata.tar.xz result/zoozve/zoozve.qcow2"
    echo "  incus launch zoozve-image zoozve --vm -c security.secureboot=false"
    echo "  incus console zoozve"

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

# Build VMware desktop VM image (skokie, aarch64)
build-desktop:
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p result/desktop

    echo "Building VMware VMDK image for desktop (skokie)..."
    nix build \
        ".#nixosConfigurations.skokie.config.system.build.images.vmware" \
        -o result/desktop/vmware

    VMDK_FILE=$(find -L result/desktop/vmware -name '*.vmdk' -type f 2>/dev/null | head -1)

    echo ""
    echo "Build complete!"
    echo "Architecture: aarch64"
    echo "Created: $VMDK_FILE"
    echo ""
    echo "Create a new VM in VMware and use this VMDK as the disk."
    echo "Recommended settings:"
    echo "  - Guest OS: Other Linux 6.x kernel 64-bit"
    echo "  - Enable 3D acceleration in Display settings"
    echo "  - Set clipboard/drag-drop to Bidirectional"

# Backward compatibility alias
alias build-vmware := build-desktop

# Build the moore server dev VM launcher (run on moore via nix-portable)
# After building, run on moore:
#   export NIX_DISK_IMAGE=/tmp/moore-vm-$USER.qcow2
#   ./result/moore/bin/run-moore-vm-vm
# Then: ssh -p 2222 whexy@localhost
build-moore-vm:
    @mkdir -p result
    @echo "Building moore VM launcher..."
    nix build .#nixosConfigurations.moore.config.system.build.vm -o result/moore
    @echo ""
    @echo "Build complete! Launcher: result/moore/bin/run-moore-vm-vm"
    @echo ""
    @echo "Run on moore:"
    @echo "  export NIX_DISK_IMAGE=/tmp/moore-vm-\$USER.qcow2"
    @echo "  ./result/moore/bin/run-moore-vm-vm"
    @echo "Then: ssh -p 2222 whexy@localhost"
