# Wayland clipboard persistence and history (Linux)
#
# wl-clipboard    – provides wl-copy / wl-paste
# wl-clip-persist – keeps a selection after the app that offered it exits
# cliphist        – clipboard history manager (persists across app exits)
#
# When the vicinae launcher is enabled it owns the history instead: its
# clipboard server stores every offer of a selection rather than the single
# "best" one wl-paste picks, and the history is searchable from the launcher.
# Running both would record each selection twice, so this module then only
# keeps the persistence bits.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.clipboard;
  vicinaeOwnsHistory = config.dotfiles.launcher.vicinae.enable;
in
{
  config = lib.mkIf (cfg.history.enable && pkgs.stdenv.hostPlatform.isLinux) {
    home.packages =
      with pkgs;
      [
        wl-clipboard
      ]
      ++ lib.optionals (!vicinaeOwnsHistory) [
        cliphist
      ];

    services.wl-clip-persist.enable = true;

    # Daemon: watch every clipboard change and store it in cliphist
    systemd.user.services.cliphist-watcher = lib.mkIf (!vicinaeOwnsHistory) {
      Unit = {
        Description = "Watch Wayland clipboard and store history with cliphist";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
