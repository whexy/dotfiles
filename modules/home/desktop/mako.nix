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
  inherit (import ./style.nix) colors font;
  makoctl = lib.getExe' config.services.mako.package "makoctl";
  vicinae = lib.getExe config.programs.vicinae.package;
in
{
  config = lib.mkIf cfg.mako.enable {
    services.mako = {
      enable = true;

      settings = {
        # Global defaults, in the desktop style (./style.nix).
        font = "${font} 10";
        anchor = "top-right";
        layer = "overlay";
        margin = "10";
        padding = "12";
        border-size = 1;
        border-radius = 8;
        default-timeout = 5000;
        max-visible = 5;
        max-icon-size = 48;

        background-color = "${colors.bg0}";
        text-color = "${colors.fg}";
        border-color = "${colors.blue}";
        progress-color = "over ${colors.bg2}";

        # Per-urgency overrides.
        "urgency=low" = {
          border-color = "${colors.gray}";
          default-timeout = 3000;
        };

        "urgency=normal" = {
          border-color = "${colors.blue}";
        };

        "urgency=critical" = {
          border-color = "${colors.red}";
          text-color = "${colors.redBright}";
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
