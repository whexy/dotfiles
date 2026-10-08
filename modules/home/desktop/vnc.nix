# Wayland VNC server for the NixOS desktop session.
args@{
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  enabled =
    osConfig != null
    && (osConfig.dotfiles.desktop.vnc.enable or false)
    && pkgs.stdenv.hostPlatform.isLinux;
in
{
  config = lib.mkIf enabled {
    systemd.user.services.wayvnc = {
      Unit = {
        Description = "Wayland VNC server";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wayvnc}/bin/wayvnc 0.0.0.0";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
