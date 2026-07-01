{ flake, ... }:
flake.lib.darwinHost {
  system = "aarch64-darwin";
  hostName = "mba";
  caps = [
    "base"
    "dev-lite"
    "gui"
  ];
  modules = [ ./hardware.nix ];
  home = ./users/whexy/home-configuration.nix;
}
