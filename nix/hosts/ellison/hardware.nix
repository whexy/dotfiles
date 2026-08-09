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

  hardware = {
    enableRedistributableFirmware = true;

    graphics = {
      enable = true;
      enable32Bit = true;
    };

    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    logitech.wireless.enable = true;

    monitors = [
      {
        connector = "HDMI-A-1";
        resolution = {
          width = 3840;
          height = 2160;
        };
        refreshRate = 120.000;
        scale = 1.5;
      }
    ];

    # Bluetooth support
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
          FastConnectable = true;
        };
        Policy = {
          AutoEnable = true;
        };
      };
    };
  };

  powerManagement.cpuFreqGovernor = "powersave";

  boot = {
    initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "ahci"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
    initrd.kernelModules = [ "dm-snapshot" ];
    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  services = {
    # Suspend the system after 20 minutes of logind-detected idleness.
    logind.settings.Login = {
      IdleAction = "suspend";
      IdleActionSec = "20min";
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
