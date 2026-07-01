# Hardware config for Proxmox VM images (used by nixos-generators)
# Provides fallback values that get overridden by proxmox-image.nix
{
  flake,
  lib,
  modulesPath,
  ...
}:

{
  nixpkgs.overlays = [ flake.lib.overlays.lkl-bigmem ];

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  system.stateVersion = "25.11";

  # Hardware-specific services
  services.qemuGuest.enable = true;

  # Fallback boot/fs config (overridden by proxmox-image module when building)
  boot.loader.grub.device = lib.mkDefault "/dev/vda";
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
