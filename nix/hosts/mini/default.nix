{ flake, ... }:
flake.lib.darwinHost {
  system = "aarch64-darwin";
  hostName = "mini";
  caps = [
    "base"
    "dev-lite"
    "gui"
  ];
  modules = [ ./hardware.nix ];
  home = ./users/whexy/home-configuration.nix;
}
