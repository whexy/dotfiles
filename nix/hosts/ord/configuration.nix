{ flake, ... }:
{
  imports =
    flake.lib.nixosHost {
      system = "x86_64-linux";
      hostName = "ord";
      caps = [
        "base"
        "dev"
        "gui"
      ];
      modules = [ ./hardware.nix ];
    }
    ++ [ flake.nixosModules.auto-upgrade ];

  dotfiles.autoUpgrade.enable = true;
}
