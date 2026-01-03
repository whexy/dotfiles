# Library functions for flake configuration
{
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
}:
{
  # Create standalone home-manager configuration
  mkHomeConfiguration = import ./mkHomeConfiguration.nix {
    inherit nixpkgs nixpkgs-unstable home-manager;
  };

  # Get overlay list for a given system
  mkOverlays = import ./overlays.nix {
    inherit nixpkgs-unstable;
  };
}
