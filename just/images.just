# The passphrase is read without echo and is only copied into the isolated
# image-builder VM before LUKS formatting; it is not stored in the image.
# Build an encrypted Incus VM image (dotfiles.platform.incusVm.encryptedDisk).
build-incus-vm HOST:
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p result/{{HOST}}

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

    echo "Building {{HOST}} Disko image script..."
    nix build \
        .#nixosConfigurations.{{HOST}}.config.system.build.diskoImagesScript \
        -o result/{{HOST}}/build

    rm -f result/{{HOST}}/{{HOST}}.qcow2 {{HOST}}.qcow2
    echo "Building encrypted qcow2 image (requires sudo)..."
    sudo result/{{HOST}}/build \
        --build-memory 4096 \
        --pre-format-files "$PASSPHRASE_FILE" /tmp/{{HOST}}-luks-passphrase
    sudo mv {{HOST}}.qcow2 result/{{HOST}}/{{HOST}}.qcow2
    sudo chown "$(id -u):$(id -g)" result/{{HOST}}/{{HOST}}.qcow2

    METADATA=$(nix build \
        .#nixosConfigurations.{{HOST}}.config.system.build.images.lxc-metadata \
        --no-link \
        --print-out-paths)
    METADATA_FILE=$(find "$METADATA/tarball" -name '*.tar.xz' -type f -print -quit)
    cp -L "$METADATA_FILE" result/{{HOST}}/incus-metadata.tar.xz

    echo ""
    echo "Build complete!"
    echo "Disk:     result/{{HOST}}/{{HOST}}.qcow2"
    echo "Metadata: result/{{HOST}}/incus-metadata.tar.xz"
    echo ""
    echo "Import on the Incus host:"
    echo "  incus image import --alias {{HOST}}-image result/{{HOST}}/incus-metadata.tar.xz result/{{HOST}}/{{HOST}}.qcow2"
    echo "  incus launch {{HOST}}-image {{HOST}} --vm -c security.secureboot=false"
    echo "  incus console {{HOST}}"

# Build an Incus system container image (rootfs + metadata tarballs).
build-incus-container HOST:
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p result/{{HOST}}

    echo "Building {{HOST}} container rootfs..."
    ROOTFS=$(nix build \
        .#nixosConfigurations.{{HOST}}.config.system.build.tarball \
        --no-link \
        --print-out-paths)
    ROOTFS_FILE=$(find "$ROOTFS/tarball" -name '*.tar.xz' -type f -print -quit)
    cp -L "$ROOTFS_FILE" result/{{HOST}}/{{HOST}}.tar.xz

    METADATA=$(nix build \
        .#nixosConfigurations.{{HOST}}.config.system.build.metadata \
        --no-link \
        --print-out-paths)
    METADATA_FILE=$(find "$METADATA/tarball" -name '*.tar.xz' -type f -print -quit)
    cp -L "$METADATA_FILE" result/{{HOST}}/incus-metadata.tar.xz
    chmod u+w result/{{HOST}}/*.tar.xz

    echo ""
    echo "Build complete!"
    echo "Rootfs:   result/{{HOST}}/{{HOST}}.tar.xz"
    echo "Metadata: result/{{HOST}}/incus-metadata.tar.xz"
    echo ""
    echo "Import on the Incus host (nesting is needed for Docker/Podman inside):"
    echo "  incus image import --alias {{HOST}}-image result/{{HOST}}/incus-metadata.tar.xz result/{{HOST}}/{{HOST}}.tar.xz"
    echo "  incus launch {{HOST}}-image {{HOST}} -c security.nesting=true"
    echo "  incus exec {{HOST}} -- login -f whexy"

# The docs site's host pages name these per-host recipes.

build-phobos: (build-incus-vm "phobos")

build-zoozve: (build-incus-vm "zoozve")

build-neith: (build-incus-container "neith")

build-deimos: (build-incus-container "deimos")

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
