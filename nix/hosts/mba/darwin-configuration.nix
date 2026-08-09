{ flake, ... }:
{
  imports = flake.lib.darwinHost {
    system = "aarch64-darwin";
    hostName = "mba";
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };
}
