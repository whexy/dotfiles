{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.virtualization;

  # Served by dockerd itself rather than by docker.socket, so it exists only
  # while Docker runs and connecting to it never starts Docker.
  dockerDirectSocket = "/run/docker-direct.sock";
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.docker.enable {
      virtualisation = {
        docker = {
          enable = true;
          enableOnBoot = !cfg.docker.onDemand;
          autoPrune.enable = cfg.docker.autoPrune || cfg.docker.serverHygiene;
          # Update 2026-01-08: enabling gVisor runtime (company contract needs it)
          extraPackages = lib.optional cfg.docker.gvisor pkgs.gvisor;
          daemon.settings = lib.mkMerge [
            (lib.mkIf cfg.docker.gvisor {
              runtimes.runsc.path = "${pkgs.gvisor}/bin/runsc";
            })
            (lib.mkIf cfg.docker.serverHygiene {
              "log-driver" = "json-file";
              "log-opts" = {
                "max-size" = "50m";
                "max-file" = "3";
              };
            })
          ];
        };

        containers = {
          enable = true;
          registries.search = [ "docker.io" ];
        };
      };
    })

    (lib.mkIf (cfg.docker.enable && cfg.docker.onDemand) {
      virtualisation.docker.daemon.settings.hosts = [ "unix://${dockerDirectSocket}" ];

      # beszel-agent polls Docker from boot on, which through docker.sock
      # would start it.
      services.beszel.agent.environment.DOCKER_HOST = "unix://${dockerDirectSocket}";

      # Requiring docker.service would start Docker for every weekly prune,
      # along with each container that has a restart policy.
      systemd.services.docker-prune = {
        requires = lib.mkForce [ ];
        serviceConfig.ExecCondition = "${config.systemd.package}/bin/systemctl is-active --quiet docker.service";
      };
    })

    (lib.mkIf cfg.podman.enable { virtualisation.podman.enable = true; })

    (lib.mkIf cfg.incus.enable {
      virtualisation.incus = {
        enable = true;
        socketActivation = cfg.incus.onDemand;
      };
    })

    (lib.mkIf (cfg.incus.enable && cfg.incus.onDemand) {
      # socketActivation drops incus-startup from boot as well. Its
      # `incusd activateifneeded` starts the daemon only for autostarting
      # instances, a network listener or scheduled snapshots, and its stop
      # shuts running instances down with the host.
      systemd.services.incus-startup.wantedBy = [ "multi-user.target" ];

      # incus.service requires lxcfs, so lxcfs starts along with it.
      systemd.services.lxcfs.wantedBy = lib.mkForce [ ];
    })
  ];
}
