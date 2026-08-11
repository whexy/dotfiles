# Monitoring group: Prometheus exporters.
{ lib, ... }:
{
  options.dotfiles.monitoring = {
    nodeExporter.enable = lib.mkEnableOption "the Prometheus node exporter (port 9100)";
  };
}
