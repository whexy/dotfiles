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

  dotfiles.system = {
    autoUpgrade.enable = true;
    fwupd.enable = true;
  };

  system.stateVersion = "26.05";
}
