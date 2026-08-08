{ flake, ... }:
{
  imports =
    flake.lib.nixosHost {
      system = "x86_64-linux";
      hostName = "remote-dev";
      caps = [
        "base"
        "dev"
      ];
      modules = [ flake.nixosModules.platform-qemu-guest-uefi-disko ];
    }
    ++ [ flake.nixosModules.auto-upgrade ];

  dotfiles.autoUpgrade.enable = true;
}
