# Personal workstation configuration (for NixOS / nix-darwin)
{ pkgs, username, ... }:
{
  imports = [
    ./base.nix
  ];

  nixpkgs.overlays = [
    (import ../overlays/mk-op-wrapped.nix)
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.users.${username} = import ../home/personal.nix;

  fonts.packages = [
    (pkgs.nerd-fonts.fira-code)
    (pkgs.nerd-fonts.jetbrains-mono)
  ];
}
