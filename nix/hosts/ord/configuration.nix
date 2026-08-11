{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "ord";
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };

  dotfiles = {
    platform.qemuGuest.enable = true;
    system.autoUpgrade.enable = true;
  };
}
