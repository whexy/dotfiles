# Overlay composition for nixpkgs
{ nixpkgs-unstable }:
{ system }:
[
  # Unstable packages overlay
  (final: prev: {
    unstable = import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  })

  # Custom overlays
  (import ../overlays/mk-op-wrapped.nix)
]
