# Development environment (for NixOS / nix-darwin hosts)
{ ... }:
{
  imports = [
    ./base.nix
    (import ../home/wrapper.nix ../home/dev.nix)
  ];

  nixpkgs.overlays = [
    (import ../overlays/mk-op-wrapped.nix)
  ];

  home-manager.useGlobalPkgs = true;
}
