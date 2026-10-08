{ lib, ... }:
{
  options.dotfiles.desktop = {
    enable = lib.mkEnableOption "desktop environment (greetd/XDG portals on NixOS, macOS desktop settings on Darwin)";
    vnc.enable = lib.mkEnableOption "VNC server for the desktop session with a noVNC web client on the tailnet (NixOS only)";
  };
}
