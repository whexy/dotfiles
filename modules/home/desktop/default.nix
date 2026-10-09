# Desktop group: notification daemon, wallpaper, display quirks.
{ lib, ... }:
{
  options.dotfiles.desktop = {
    mako.enable = lib.mkEnableOption "the mako notification daemon (Wayland)";
    udiskie.enable = lib.mkEnableOption "automounting removable media with udiskie";
    wallpaper.enable = lib.mkEnableOption "desktop wallpaper";
    macbookScreenDensity.enable = lib.mkEnableOption "GTK text-scaling compensation on MacBook Retina panels";
  };

  imports = [
    ./mako.nix
    ./udiskie.nix
    ./wallpaper.nix
    ./macbook-screen-density.nix
  ];
}
