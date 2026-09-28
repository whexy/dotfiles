# Power group: keeping a machine awake and running unattended.
{ lib, ... }:
{
  options.dotfiles.power = {
    alwaysOn.enable = lib.mkEnableOption ''
      always-on server power management (never sleep, restart after a power
      failure or freeze, wake on LAN); only has an effect on Darwin'';
  };
}
