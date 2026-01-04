# Function to create standalone home-manager configurations
{
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
}:
let

  nixpkgsSettings = import ../overlays/nixpkgs-settings.nix {
    inputs = { inherit nixpkgs-unstable; };
  };

  pkgs = import nixpkgs {
    system = builtins.currentSystem;
    inherit (nixpkgsSettings.nixpkgs) overlays;
    inherit (nixpkgsSettings.nixpkgs) config;
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
