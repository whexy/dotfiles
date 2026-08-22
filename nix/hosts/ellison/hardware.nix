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
      connector = "DP-3";
      resolution = {
        width = 3840;
        height = 2160;
      };
      refreshRate = 165.000;
      scale = 1.5;
    }
  ];

  hardware = {
    enableRedistributableFirmware = true;

    graphics = {
      enable = true;
      enable32Bit = true;
    };

    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    logitech.wireless.enable = true;

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

  # Enable Wake-on-LAN on the onboard Ethernet adapter
  networking.interfaces.enp5s0.wakeOnLan.enable = true;

  powerManagement.cpuFreqGovernor = "powersave";

  boot = {
    # With the amd-pstate-epp driver, the governor only selects the mechanism;
    # actual performance scaling is controlled by the EPP hint.
    kernel.sysfs.devices.system.cpu."cpu[0-9]*".cpufreq.energy_performance_preference = "balance_power";

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
