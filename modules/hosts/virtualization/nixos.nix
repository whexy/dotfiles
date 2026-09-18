{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.virtualization;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.docker.enable {
      virtualisation = {
        docker = {
          enable = true;
          autoPrune.enable = cfg.docker.serverHygiene;
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

    (lib.mkIf cfg.podman.enable { virtualisation.podman.enable = true; })

    (lib.mkIf cfg.incus.enable { virtualisation.incus.enable = true; })
  ];
}
