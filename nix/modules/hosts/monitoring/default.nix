# Monitoring group: Prometheus exporters and the Beszel agent.
{ lib, ... }:
{
  options.dotfiles.monitoring = {
    nodeExporter.enable = lib.mkEnableOption "the Prometheus node exporter (port 9100)";
    beszel.enable = lib.mkEnableOption "the Beszel monitoring agent (port 45876)";
  };
}
