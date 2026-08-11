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
    };

    # Work around nix-darwin string comparison: the existing system user has
    # /private/var/… but the module defaults to /var/… (a symlink on macOS).
    users.users._prometheus-node-exporter.home = lib.mkForce "/private/var/lib/prometheus-node-exporter";
  };
}
