# Wayland VNC server for the NixOS desktop session, and the noVNC web client
# that browsers on the tailnet use to reach it.
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

  novncPort = toString 6080;
  tailscale = lib.getExe osConfig.services.tailscale.package;

  # vnc.html doubles as the index and reads its defaults from defaults.json,
  # so the bare tailnet URL opens straight into a scaled session.
  novncDefaults = pkgs.writeText "novnc-defaults.json" (
    builtins.toJSON {
      autoconnect = true;
      reconnect = true;
      resize = "scale";
    }
  );
  novncWeb = pkgs.runCommand "novnc-web" { } ''
    mkdir $out
    ln -s ${pkgs.novnc}/share/webapps/novnc/* $out/
    ln -s vnc.html $out/index.html
    ln -s ${novncDefaults} $out/defaults.json
  '';
in
{
  config = lib.mkIf enabled {
    systemd.user.services = {
      wayvnc = {
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

      novnc = {
        Unit = {
          Description = "noVNC web client for wayvnc";
          After = [ "wayvnc.service" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe' pkgs.python3Packages.websockify "websockify"} --web=${novncWeb} --file-only 127.0.0.1:${novncPort} 127.0.0.1:5900";
          # Serve fails until tailscaled is logged in; the restart delay keeps
          # retries under systemd's start limit.
          ExecStartPost = "${tailscale} serve --bg --https=${novncPort} http://127.0.0.1:${novncPort}";
          ExecStopPost = "-${tailscale} serve --https=${novncPort} off";
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
