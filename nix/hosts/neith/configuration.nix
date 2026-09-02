{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "neith";
    incusContainer = true;
    caps = [
      "base"
      "dev"
    ];
    modules = [ ./nvidia.nix ];
  };

  dotfiles.system.autoUpgrade.enable = true;

  system.stateVersion = "26.05";
}
