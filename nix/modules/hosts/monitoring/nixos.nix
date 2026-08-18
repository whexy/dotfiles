{ config, lib, ... }:
let
  cfg = config.dotfiles.monitoring;
in
{
  # Export metrics
  config = lib.mkMerge [
    (lib.mkIf cfg.nodeExporter.enable {
      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = "0.0.0.0";
        port = 9100;
        enabledCollectors = [
          "systemd"
          "processes"
        ];
      };
    })

    (lib.mkIf cfg.beszel.enable {
      age.identityPaths = [ "/home/${config.dotfiles.host.username}/.config/agenix/key.txt" ];
      age.secrets.beszel-token.file = ../../../../secrets/beszel-token.age;

      services.beszel.agent = {
        enable = true;
        environment = {
          KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBlZA5rswnKHS8M8ZMxqTxlJ8FM0Y9Pt9jrt52kGfC3m";
          HUB_URL = "https://beszel.at-basking.ts.net";
        };
        environmentFile = config.age.secrets.beszel-token.path;
      };
    })
  ];
}
