{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.monitoring;
  upgradeStatus = "${config.dotfiles.system.autoUpgrade.stateDir}/status.json";

  # Beszel's Updates column counts what the host's package manager reports,
  # and the agent picks apt when it finds apt-get and dpkg-query on its PATH.
  # These stand-ins, on the agent's PATH alone, report the dotfiles checkout
  # as the one package: pending while dotfiles-upgraded has not applied the
  # tip of master, and a security update once it gave up switching to it.
  aptGet = pkgs.writeShellApplication {
    name = "apt-get";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      if [ "$*" != "-s dist-upgrade" ]; then
        echo "apt-get: only Beszel's update check is emulated" >&2
        exit 100
      fi
      # apt's simulation line, as Beszel parses it:
      #   Inst <name> [<installed>] (<candidate> <origin>)
      # where "-security" in the origin marks a security update.
      jq -r '
        select(.tipSha != null and .tipSha != "" and .tipSha != .lastSuccessSha)
        | (.lastSuccessSha // "" | if . == "" then "unknown" else .[0:7] end) as $installed
        | (if .phase == "switch-failed" then "dotfiles-security" else "dotfiles" end) as $origin
        | "Inst dotfiles:\(.phase) [\($installed)] (\(.tipSha[0:7]) \($origin))"
      ' ${upgradeStatus}
    '';
  };
  dpkgQuery = pkgs.writeShellApplication {
    name = "dpkg-query";
    text = ''[ "$*" = "-W apt" ]'';
  };
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
      age.secrets.beszel-token.file = ../../../secrets/beszel-token.age;

      services.beszel.agent = {
        enable = true;
        # Package update reporting arrived in 0.21; the release channel has
        # 0.18.
        package = pkgs.unstable.beszel;
        environment = {
          KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBlZA5rswnKHS8M8ZMxqTxlJ8FM0Y9Pt9jrt52kGfC3m";
          HUB_URL = "https://if.clusters.work";
        };
        environmentFile = config.age.secrets.beszel-token.path;
      };
    })

    (lib.mkIf (cfg.beszel.enable && config.dotfiles.system.autoUpgrade.enable) {
      services.beszel.agent = {
        extraPath = [
          aptGet
          dpkgQuery
        ];
        # Reading status.json is free, and the default hour would show a
        # switch long after it happened.
        environment.PACKAGE_UPDATES_INTERVAL = "1m";
      };
    })
  ];
}
