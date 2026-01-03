# Development environment (for NixOS / nix-darwin hosts)
{ username, ... }:
{
  imports = [
    ./base.nix
  ];

  nixpkgs.overlays = [
    (import ../overlays/mk-op-wrapped.nix)
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.users.${username} = import ../home/dev.nix;
}
