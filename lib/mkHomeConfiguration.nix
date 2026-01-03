# Function to create standalone home-manager configurations
{
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
}:
{ system }:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      })
      (import ../overlays/mk-op-wrapped.nix)
    ];
  };
  username = builtins.getEnv "USER";
  homeDirectory = builtins.getEnv "HOME";
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    ../home/dev.nix
    {
      home.username = username;
      home.homeDirectory = homeDirectory;
    }
  ];
}
