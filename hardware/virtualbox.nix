# Hardware config for VirtualBox VM images (used by nixos-rebuild build-image)
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

  # Configure the VirtualBox image module
  image.modules.virtualbox = {
    # 16GB RAM for the VM
    virtualbox.memorySize = 16 * 1024;

    # 50GB disk size (larger closure needs more space)
    virtualisation.diskSize = 50 * 1024;

    # VirtualBox guest additions for better integration
    virtualisation.virtualbox.guest = {
      enable = true;
      clipboard = true;
      seamless = true;
      dragAndDrop = true;
    };
  };

  # Fallback boot/fs config (for non-image builds)
  boot.loader.grub.device = lib.mkDefault "/dev/sda";
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
