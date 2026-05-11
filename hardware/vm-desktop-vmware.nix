# Hardware config for VMware VM images
# Supports both x86_64 and aarch64 architectures
# Build image with: just build-desktop vmware [x86_64|aarch64]
{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./vm-desktop-base.nix
  ];

  # Configure the VMware image module
  image.modules.vmware = {
    # Auto-size disk based on closure
    vmware.baseImageSize = "auto";

    # Sparse format good for development
    vmware.vmSubformat = "monolithicSparse";

    # VMware guest support (image-specific)
    virtualisation.vmware.guest = {
      enable = true;
      headless = false; # Enable GUI/Wayland features
    };
  };

  # VMware guest tools for the running system
  virtualisation.vmware.guest = {
    enable = true;
    headless = false;
  };

  # Workaround for unreliable VMware host DNS — prepend public resolvers
  networking.networkmanager.insertNameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  # Kernel modules for VMware
  boot.initrd.availableKernelModules = [
    "mptspi" # SCSI controller
    "ahci" # SATA controller
    "sd_mod" # SCSI disk
    "sr_mod" # SCSI CD-ROM
  ];

  # x86-only paravirtualized SCSI driver
  boot.initrd.kernelModules = lib.optionals pkgs.stdenv.hostPlatform.isx86 [
    "vmw_pvscsi" # Paravirtualized SCSI
  ];

  boot.kernelModules = [
    "vmw_balloon" # Memory ballooning
    "vmw_vmci" # Guest-host communication
  ];
}
