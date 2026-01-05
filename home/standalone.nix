# Standalone home-manager configuration for non-NixOS Linux systems
{
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
}:
let
  system = builtins.currentSystem;

  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (import ../overlays/mk-op-wrapped.nix)
      (final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config = prev.config;
        };
      })
    ];
  };

  username = builtins.getEnv "USER";
  homeDirectory = builtins.getEnv "HOME";
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    ./base.nix
    ./dev.nix
    {
      home.username = username;
      home.homeDirectory = homeDirectory;
    }
  ];
}
