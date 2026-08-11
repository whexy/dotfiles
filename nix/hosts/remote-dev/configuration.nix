{ flake, ... }:
{
  imports = flake.lib.nixosHost {
    system = "x86_64-linux";
    hostName = "remote-dev";
    caps = [
      "base"
      "dev"
    ];
  };

  dotfiles.system.autoUpgrade.enable = true;

  dotfiles.platform.qemuGuest.enable = true;
}
