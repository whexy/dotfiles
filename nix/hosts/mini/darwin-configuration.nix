{ flake, ... }:
{
  imports = flake.lib.darwinHost {
    system = "aarch64-darwin";
    hostName = "mini";
    caps = [
      "base"
      "dev-lite"
      "gui"
    ];
    modules = [ ./hardware.nix ];
  };
}
