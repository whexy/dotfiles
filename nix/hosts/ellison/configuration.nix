{ flake, ... }:
{
  imports =
    flake.lib.nixosHost {
      system = "x86_64-linux";
      hostName = "ellison";
      caps = [
        "base"
        "dev"
        "gui"
      ];
      modules = [
        ./disk-config.nix
        ./hardware.nix
      ];
    }
    ++ [ flake.nixosModules.auto-upgrade ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  hardware = {
    enableRedistributableFirmware = true;
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  services.fstrim.enable = true;

  dotfiles.autoUpgrade.enable = true;
  system.stateVersion = "26.05";
}
