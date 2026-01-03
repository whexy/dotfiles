# Base home-manager configuration
{ pkgs, lib, ... }:
let
  packages = import ./packages.nix { inherit pkgs lib; };
in
{
  imports = [
    ./base/shell.nix
    ./base/tmux.nix
    ./base/vim.nix
  ];

  home.stateVersion = "25.11";
  home.packages = packages.base;
}
