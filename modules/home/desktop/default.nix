# Desktop group: notification daemon, session services, wallpaper, display
# quirks.
{ config, lib, ... }:
{
  options.dotfiles.desktop = {
    mako.enable = lib.mkEnableOption "the mako notification daemon (Wayland)";
    udiskie.enable = lib.mkEnableOption "automounting removable media with udiskie";
    session.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.dotfiles.wm.niri.enable;
      defaultText = lib.literalExpression "config.dotfiles.wm.niri.enable";
      description = "Whether to run the Wayland session's lock screen and tray applets.";
    };
    wallpaper.enable = lib.mkEnableOption "desktop wallpaper";
    macbookScreenDensity.enable = lib.mkEnableOption "GTK text-scaling compensation on MacBook Retina panels";
  };

  imports = [
    ./mako.nix
    ./session.nix
    ./udiskie.nix
    ./wallpaper.nix
    ./macbook-screen-density.nix
  ];
}
