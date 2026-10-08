# Power NixOS configuration: an always-on machine that never sleeps, and an
# optional CPU policy that trades power for performance.
{ config, lib, ... }:
let
  cfg = config.dotfiles.power;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.alwaysOn.enable {
      # Refuse every sleep state, so a stray key, menu entry, or
      # `systemctl suspend` cannot take the machine off the network.
      systemd.sleep.settings.Sleep = {
        AllowSuspend = "no";
        AllowHibernation = "no";
        AllowHybridSleep = "no";
        AllowSuspendThenHibernate = "no";
      };

      services.logind.settings.Login = {
        IdleAction = "ignore";
        HandleSuspendKey = "ignore";
        HandleHibernateKey = "ignore";
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
      };
    })

    (lib.mkIf cfg.performance.enable {
      # With intel_pstate or amd-pstate in active mode, this governor also
      # pins the energy-performance preference to "performance".
      powerManagement.cpuFreqGovernor = "performance";
    })
  ];
}
