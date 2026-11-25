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

      publishAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "127.0.0.1";
        description = ''
          The host address `docker run -p` binds when it names none. Docker's
          port forwarding bypasses the NixOS firewall, so a host on a public
          network sets this to keep published ports off it.
        '';
      };
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
