# Power group: keeping a machine awake and running unattended.
{ lib, ... }:
{
  options.dotfiles.power = {
    alwaysOn.enable = lib.mkEnableOption ''
      always-on server power management: never sleep, so the machine stays
      reachable over the network while its displays blank and its session
      locks (Darwin also restarts after a power failure or freeze and wakes
      on LAN)'';
    performance.enable = lib.mkEnableOption ''
      the performance CPU frequency governor instead of power saving; only has
      an effect on NixOS'';
  };
}
