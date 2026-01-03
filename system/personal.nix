# Personal workstation configuration (for NixOS / nix-darwin)
{ pkgs, ... }:
{
  imports = [
    ./base.nix
    (import ../home/wrapper.nix ../home/personal.nix)
  ];

  nixpkgs.overlays = [
    (import ../overlays/mk-op-wrapped.nix)
  ];

  home-manager.useGlobalPkgs = true;

  fonts.packages = [
    (pkgs.nerd-fonts.fira-code)
    (pkgs.nerd-fonts.jetbrains-mono)
  ];
}
