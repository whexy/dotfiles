{ flake, ... }:
{
  dotfiles.system.autoUpgrade.enable = true;

  imports = flake.lib.darwinHost {
    system = "aarch64-darwin";
    hostName = "sheridan";
    caps = [
      "base"
      "dev-lite"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };
}
