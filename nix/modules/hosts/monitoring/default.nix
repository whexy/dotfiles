# Monitoring group: Prometheus exporters and the Beszel agent.
{ lib, ... }:
{
  options.dotfiles.monitoring = {
    nodeExporter.enable = lib.mkEnableOption "the Prometheus node exporter (port 9100)";

    beszel = {
      enable = lib.mkEnableOption "the Beszel monitoring agent (port 45876)";

      key = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          SSH public key from the Beszel hub, used to authorize connections.
          Obtain it from the hub's "Add System" dialog.
        '';
      };

      hubUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          URL of the Beszel hub. Together with the universal token (from the
          agenix beszel-token secret) this lets the agent auto-register.
        '';
      };
    };
  };
}
