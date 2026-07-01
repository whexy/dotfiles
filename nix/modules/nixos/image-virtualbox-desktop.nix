# Hardware config for VirtualBox VM images (used by nixos-rebuild build-image)
{
  flake,
  lib,
  pkgs,
  modulesPath,
  username,
  ...
}:

{
  nixpkgs.overlays = [ flake.lib.overlays.lkl-bigmem ];

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

    # VirtualBox guest additions for better integration (image-specific options)
    virtualisation.virtualbox.guest = {
      enable = true;
      clipboard = true;
      seamless = true;
      dragAndDrop = true;
    };
  };

  # VirtualBox guest additions for the running system
  virtualisation.virtualbox.guest = {
    enable = true;
    clipboard = true;
  };

  # Hardware graphics (may help with OpenGL support)
  hardware.graphics = {
    enable = true;
  };

  # Greetd display manager with auto-login to niri
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        user = "greeter";
      };
      initial_session = {
        command = "niri-session";
        user = username;
      };
    };
  };

  # Fallback boot/fs config (for non-image builds)
  boot.loader.grub.device = lib.mkDefault "/dev/sda";
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
