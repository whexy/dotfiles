# Desktop NixOS system configuration (Wayland/niri session): display manager,
# XDG portals, GSettings backend, and Bluetooth tray integration.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.desktop;
  username = config.dotfiles.host.username;
in
{
  config = lib.mkIf cfg.enable {
    services = {
      # Blueman provides the Bluetooth manager and D-Bus backend; Home Manager
      # starts its tray applet after the session tray target is available.
      blueman.enable = true;

      # Greetd display manager with auto-login to niri
      greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
            user = "greeter";
          };
          initial_session = {
            command = "niri-session";
            user = username;
          };
        };
      };
    };

    # XDG Desktop Portal: provides file chooser, screen cast, notifications, etc.
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
      config.common.default = [ "gnome" ];
    };

    # Required for xdg-desktop-portal with home-manager
    environment.pathsToLink = [
      "/share/applications"
      "/share/xdg-desktop-portal"
    ];

    # dconf: GSettings storage backend. Required for home-manager's
    # dconf.settings to take effect (used by macbook-screen-density.nix to
    # set text-scaling-factor on hosts sharing a MacBook Retina panel).
    programs.dconf.enable = true;
  };
}
