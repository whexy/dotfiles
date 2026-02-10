# Hardware config for VMware VM images (used by nixos-rebuild build-image)
{
  lib,
  pkgs,
  modulesPath,
  username,
  ...
}:

{
  imports = [
    (modulesPath + "/image/images.nix")
  ];

  system.stateVersion = "25.11";

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

  # Hardware graphics for vmwgfx driver (better OpenGL/Wayland than VirtualBox)
  hardware.graphics = {
    enable = true;
  };

  # Kernel modules for VMware
  boot.initrd.availableKernelModules = [
    "mptspi" # SCSI controller
    "ahci" # SATA controller
    "sd_mod" # SCSI disk
    "sr_mod" # SCSI CD-ROM
  ];

  boot.initrd.kernelModules = lib.optionals pkgs.stdenv.hostPlatform.isx86 [
    "vmw_pvscsi" # Paravirtualized SCSI
  ];

  boot.kernelModules = [
    "vmw_balloon" # Memory ballooning
    "vmw_vmci" # Guest-host communication
  ];

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

  # EFI boot config for VMware
  boot.loader.grub = {
    device = lib.mkDefault "nodev";
    efiSupport = lib.mkDefault true;
    efiInstallAsRemovable = lib.mkDefault true;
  };

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
}
