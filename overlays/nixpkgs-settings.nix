{ inputs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    # customized overlays
    (import ./mk-op-wrapped.nix)

    # Add unstable channel
    (final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (prev) system;
        config = prev.config;
      };
    })
  ];
}
