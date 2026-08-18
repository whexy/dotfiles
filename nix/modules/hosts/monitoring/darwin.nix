{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.monitoring;
in
{
  config = lib.mkMerge [
    # Export metrics
    (lib.mkIf cfg.nodeExporter.enable {
      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = "0.0.0.0";
        port = 9100;
      };

      # Work around nix-darwin string comparison: the existing system user has
      # /private/var/… but the module defaults to /var/… (a symlink on macOS).
      users.users._prometheus-node-exporter.home = lib.mkForce "/private/var/lib/prometheus-node-exporter";
    })

    (lib.mkIf cfg.beszel.enable {
      warnings =
        lib.optional (cfg.beszel.key == "")
          "dotfiles.monitoring.beszel is enabled but beszel.key is empty; the agent cannot connect to the hub until a key is set";

      # The universal token is an agenix secret (secrets/beszel-token.age,
      # encrypted to the user age key, so use that key as the identity).
      age.identityPaths = [ "/Users/${config.dotfiles.host.username}/.config/agenix/key.txt" ];
      age.secrets.beszel-token.file = ../../../../secrets/beszel-token.age;

      # nix-darwin has no beszel module; run the agent as a root launchd daemon.
      launchd.daemons.beszel-agent = {
        script = ''
          # Source TOKEN (hub universal token) decrypted by agenix.
          set -a
          . ${config.age.secrets.beszel-token.path}
          set +a

          exec ${lib.getExe' pkgs.beszel "beszel-agent"}
        '';
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          EnvironmentVariables = {
            KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBlZA5rswnKHS8M8ZMxqTxlJ8FM0Y9Pt9jrt52kGfC3m";
            HUB_URL = "https://beszel.at-basking.ts.net";
            PORT = "45876";
          };
          StandardOutPath = "/var/log/beszel-agent.log";
          StandardErrorPath = "/var/log/beszel-agent.log";
        };
      };
    })
  ];
}
