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
      warnings =
        lib.optional (cfg.beszel.key == "")
          "dotfiles.monitoring.beszel is enabled but beszel.key is empty; the agent cannot connect to the hub until a key is set";

      # The universal token is an agenix secret (secrets/beszel-token.age,
      # encrypted to the user age key, so use that key as the identity).
      age.identityPaths = [ "/home/${config.dotfiles.host.username}/.config/agenix/key.txt" ];
      age.secrets.beszel-token.file = ../../../../secrets/beszel-token.age;

      services.beszel.agent = {
        enable = true;
        environment = {
          KEY = cfg.beszel.key;
        }
        // lib.optionalAttrs (cfg.beszel.hubUrl != "") {
          HUB_URL = cfg.beszel.hubUrl;
        };
        # Provides TOKEN, the hub's universal token for auto-registration.
        environmentFile = config.age.secrets.beszel-token.path;
      };
    })
  ];
}
