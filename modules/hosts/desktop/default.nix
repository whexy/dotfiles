{ lib, ... }:
{
  options.dotfiles.desktop = {
    enable = lib.mkEnableOption "desktop environment (greetd/XDG portals on NixOS, macOS desktop settings on Darwin)";
    vnc.enable = lib.mkEnableOption "VNC over Tailscale (NixOS: server for the desktop session; macOS: TigerVNC viewer)";
  };
}
