# Mako notification daemon (Wayland, Linux only)
#
# Mako is DBus-activated: home-manager installs the org.freedesktop.Notifications
# service file, so the daemon starts on demand the first time an application
# emits a notification. No spawn-at-startup entry in niri is required.
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.desktop;
  makoctl = lib.getExe' config.services.mako.package "makoctl";
  vicinae = lib.getExe config.programs.vicinae.package;
in
{
  config = lib.mkIf cfg.mako.enable {
    services.mako = {
      enable = true;

      settings = {
        # Global defaults — Gruvbox palette matching waybar.nix.
        font = "JetBrainsMono Nerd Font 10";
        anchor = "top-right";
        layer = "overlay";
        margin = "10";
        padding = "12";
        border-size = 1;
        border-radius = 8;
        default-timeout = 5000;
        max-visible = 5;
        max-icon-size = 48;

        background-color = "#282828";
        text-color = "#ebdbb2";
        border-color = "#458588";
        progress-color = "over #504945";

        # Per-urgency overrides.
        "urgency=low" = {
          border-color = "#928374";
          default-timeout = 3000;
        };

        "urgency=normal" = {
          border-color = "#458588";
        };

        "urgency=critical" = {
          border-color = "#cc241d";
          text-color = "#fb4934";
          # Critical notifications never auto-dismiss.
          default-timeout = 0;
        };

        # Blueman asks for pairing confirmation through Confirm/Deny actions
        # without a default action, so mako's plain click would only dismiss
        # the request. Keep it on screen and pick the action from a menu.
        "app-name=blueman actionable" = {
          default-timeout = 0;
          on-button-left = lib.mkIf config.programs.vicinae.enable ''exec ${makoctl} menu -n "$id" -- ${vicinae} dmenu -p "Pairing request"'';
        };
      };
    };
  };
}
