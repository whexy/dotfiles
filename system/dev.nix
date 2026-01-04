# Development environment (for NixOS / nix-darwin hosts)
{ username, ... }:
{
  imports = [
    ./base.nix
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.users.${username} = import ../home/dev.nix;
}
