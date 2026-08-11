{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "mudd";
    caps = [
      "base"
      "dev"
    ];
  };

  dotfiles.system.autoUpgrade.enable = true;

  dotfiles.platform.qemuGuest.enable = true;
}
