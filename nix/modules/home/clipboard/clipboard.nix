# Wayland clipboard persistence and history (Linux)
#
# wl-clipboard  – provides wl-copy / wl-paste
# cliphist      – clipboard history manager (persists across app exits)
# fuzzel        – Wayland-native app launcher (also used for clipboard picker)
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.clipboard;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  config = lib.mkIf cfg.history.enable (
    if isDarwin then
      { }
    else
      {
        home.packages = with pkgs; [
          wl-clipboard
          cliphist
          fuzzel
        ];

        # Daemon: watch every clipboard change and store it in cliphist
        systemd.user.services.cliphist-watcher = {
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
      }
  );
}
