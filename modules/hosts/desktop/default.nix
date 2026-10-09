{ lib, ... }:
{
  options.dotfiles.desktop = {
    enable = lib.mkEnableOption "desktop environment (greetd/XDG portals on NixOS, macOS desktop settings on Darwin)";
  };
}
