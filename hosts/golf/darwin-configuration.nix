{ flake, ... }:
{
  imports = flake.lib.darwinHost {
    system = "aarch64-darwin";
    hostName = "golf";
    caps = [
      "base"
      "dev"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };
}
