# Add nixpkgs-unstable as pkgs.unstable
# Requires: inputs.nixpkgs-unstable
{ nixpkgs-unstable }:
final: prev: {
  unstable = import nixpkgs-unstable {
    inherit (prev.stdenv.hostPlatform) system;
    inherit (prev) config;
  };
}
