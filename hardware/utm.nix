# Hardware config for UTM (QEMU-based macOS VM)
# Build image with: just build-utm
{
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/image/images.nix")
  ];

  system.stateVersion = "25.11";

  # Bootloader - systemd-boot for EFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # Allow resizing the disk in UTM after deployment
  boot.growPartition = true;

  # Ensure virtio-gpu driver is loaded for display output in UTM
  boot.initrd.kernelModules = [ "virtio_gpu" ];

  # Guest services
  services.qemuGuest.enable = true;

  # SPICE agent for clipboard sharing and dynamic display resolution
  services.spice-vdagentd.enable = true;

  # Hardware graphics
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
