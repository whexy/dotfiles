# Standalone home-manager configuration for non-NixOS Linux
# Simply imports dev.nix - all the real config lives there
{ lib, ... }:
{
  imports = [ ./dev.nix ];

  home.username = lib.mkDefault "whexy";
  home.homeDirectory = lib.mkDefault "/home/whexy";
}
