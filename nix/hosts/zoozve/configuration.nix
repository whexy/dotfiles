{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "zoozve";
    caps = [
      "base"
      "dev"
    ];
    modules = [ ./disk-config.nix ];
  };

  dotfiles = {
    system.autoUpgrade.enable = true;
    platform.incusVm.enable = true;
  };

  system.stateVersion = "26.05";
}
