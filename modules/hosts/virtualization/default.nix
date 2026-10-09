# Virtualization group: Docker, Podman, Incus.
{ lib, ... }:
{
  options.dotfiles.virtualization = {
    docker = {
      enable = lib.mkEnableOption "Docker";

      gvisor = lib.mkEnableOption "the gVisor (runsc) container runtime";

      onDemand = lib.mkEnableOption ''
        starting dockerd on first use of its socket instead of at boot.
        Containers with a restart policy come up only once Docker starts'';

      autoPrune = lib.mkEnableOption ''
        a weekly `docker system prune` of stopped containers, unused
        networks, dangling images and dangling build cache; tagged images
        and volumes are kept'';

      serverHygiene = lib.mkEnableOption ''
        server-oriented Docker hygiene: automatic image pruning and
        bounded json-file container logs'';
    };

    podman.enable = lib.mkEnableOption "Podman";

    incus = {
      enable = lib.mkEnableOption "Incus system containers and VMs";

      onDemand = lib.mkEnableOption ''
        starting incusd on first use of its socket instead of at boot.
        Instances that autostart still bring it up at boot'';
    };
  };
}
