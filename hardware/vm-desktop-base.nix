# Base hardware configuration for desktop VM images
# Shared by both UTM and VMware backends
{
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/image/images.nix")
  ];

  system.stateVersion = "25.11";

  boot = {
    # Bootloader - systemd-boot for EFI (works on both UTM and VMware)
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = false;

    # Allow resizing the disk after deployment
    growPartition = true;
  };

  # Hardware graphics support
  hardware.graphics = {
    enable = true;
  };

  # Filesystem layout (matches disk-image.nix defaults)
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
}
