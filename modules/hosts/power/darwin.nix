# Power Darwin configuration: an always-on Mac that stays reachable over the
# network and boots by itself after an outage.
{ config, lib, ... }:
{
  config = lib.mkIf config.dotfiles.power.alwaysOn.enable {
    power = {
      restartAfterPowerFailure = true;
      restartAfterFreeze = true;
      sleep = {
        computer = "never";
        harddisk = "never";
      };
    };

    # pmset settings nix-darwin has no options for. Power Nap's dark wakes
    # drop network interfaces if the Mac is ever put to sleep by hand.
    system.activationScripts.power.text = lib.mkAfter ''
      /usr/bin/pmset -a powernap 0 womp 1 tcpkeepalive 1 ttyskeepawake 1
    '';
  };
}
