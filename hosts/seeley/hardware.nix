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

  # The lab port only leases to MACs registered with CS IT. This one is
  # registered as xiaoqiang and holds a fixed reservation; the DHCP hostname
  # does not matter.
  #
  # NetworkManager takes the device once udev finishes its add event and
  # keeps the address it finds (ethernet.macAddress = "preserve"), so the
  # address is set during that event, matched by PCI path because the device
  # still has its kernel name; networking.interfaces links match the new name
  # and apply only after the rename. Only the first matching .link file
  # applies, so this one also sets the name and Wake-on-LAN.
  systemd.network.links."10-enp0s31f6" = {
    matchConfig.Path = "pci-0000:00:1f.6";
    linkConfig = {
      Name = "enp0s31f6";
      MACAddress = "5C:02:14:45:67:32";
      WakeOnLan = "magic";
    };
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
