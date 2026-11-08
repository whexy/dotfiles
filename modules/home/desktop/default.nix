# Desktop group: notification daemon, session services, wallpaper, display
# quirks.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.dotfiles.desktop = {
    xdg.enable = lib.mkEnableOption "XDG user directories and default applications (Linux)";
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

  config = lib.mkIf config.dotfiles.desktop.xdg.enable {
    xdg = {
      userDirs = {
        enable = true;
        createDirectories = true;
      };

      mimeApps = {
        enable = true;
        defaultApplications = {
          "application/pdf" = "firefox.desktop";
          "inode/directory" = "org.gnome.Nautilus.desktop";
          "text/html" = "firefox.desktop";
          "x-scheme-handler/http" = "firefox.desktop";
          "x-scheme-handler/https" = "firefox.desktop";
        };
        defaultApplicationPackages = [ pkgs.vlc ];
      };
    };
  };
}
