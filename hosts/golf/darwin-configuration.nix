{ flake, hostName, ... }:
{
  dotfiles.system.autoUpgrade.enable = true;

  imports = flake.lib.darwinHost {
    system = "aarch64-darwin";
    inherit hostName;
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };
}
