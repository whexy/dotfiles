# Mako notification daemon (Wayland, Linux only)
#
# Mako is DBus-activated: home-manager installs the org.freedesktop.Notifications
# service file, so the daemon starts on demand the first time an application
# emits a notification. No spawn-at-startup entry in niri is required.
{
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
    };
  };
}
