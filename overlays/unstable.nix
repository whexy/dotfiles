# Add nixpkgs-unstable as pkgs.unstable
# Requires: inputs.nixpkgs-unstable
{ nixpkgs-unstable }:
final: prev: {
  unstable = import nixpkgs-unstable {
    inherit (prev) system;
    config = prev.config;
  };
}
