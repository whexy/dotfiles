# Virtualization group: Docker, Podman, Incus.
{ lib, ... }:
{
  options.dotfiles.virtualization = {
    docker = {
      enable = lib.mkEnableOption "Docker";

      gvisor = lib.mkEnableOption "the gVisor (runsc) container runtime";

      serverHygiene = lib.mkEnableOption ''
        server-oriented Docker hygiene: automatic image pruning and
        bounded json-file container logs'';
    };

    podman.enable = lib.mkEnableOption "Podman";

    incus.enable = lib.mkEnableOption "Incus system containers and VMs";
  };
}
