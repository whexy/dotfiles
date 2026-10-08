{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "seeley";
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [
      ./disk-config.nix
      ./hardware.nix
      ./nvidia.nix
    ];
  };

  services = {
    fstrim.enable = true;
    btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" ];
    };
  };

  dotfiles = {
    system = {
      autoUpgrade.enable = true;
      fwupd.enable = true;
    };
    # A lab desktop that mostly serves as a headless server, on someone
    # else's power bill.
    power = {
      alwaysOn.enable = true;
      performance.enable = true;
    };
  };

  system.stateVersion = "26.05";
}
