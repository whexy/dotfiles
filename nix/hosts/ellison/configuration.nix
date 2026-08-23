{ flake, ... }:
{
  imports = flake.lib.nixosHost {
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
  };

  services.fstrim.enable = true;

  dotfiles = {
    system = {
      autoUpgrade.enable = true;
      fwupd.enable = true;
    };
    gaming.enable = true;
  };
  system.stateVersion = "26.05";
}
