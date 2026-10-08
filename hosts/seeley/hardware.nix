{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  dotfiles.hardware.monitors = [
    {
      connector = "DP-2";
      resolution = {
        width = 2560;
        height = 1440;
      };
      scale = 1.0;
    }
  ];

  hardware = {
    enableRedistributableFirmware = true;

    graphics = {
      enable = true;
      enable32Bit = true;
    };

    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  networking.interfaces.enp0s31f6.wakeOnLan.enable = true;

  # The lab port only leases to MACs registered with CS IT. This one is
  # registered as xiaoqiang and holds a fixed reservation; the DHCP hostname
  # does not matter.
  networking.networkmanager.ensureProfiles.profiles.campus = {
    connection = {
      id = "campus";
      type = "ethernet";
      interface-name = "enp0s31f6";
    };
    ethernet.cloned-mac-address = "5C:02:14:45:67:32";
  };

  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usbhid"
      "uas"
      "sd_mod"
    ];
    kernelModules = [ "kvm-intel" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
