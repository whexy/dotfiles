{ config, lib, ... }:
let
  cfg = config.dotfiles.monitoring;
in
{
  # Export metrics
  config = lib.mkIf cfg.nodeExporter.enable {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9100;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };
  };
}
