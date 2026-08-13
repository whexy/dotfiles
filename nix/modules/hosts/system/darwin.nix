# System Darwin configuration: nix-darwin state version and auto-upgrade.
{ config, lib, ... }:
let
  cfg = config.dotfiles.system;
in
{
  config = lib.mkMerge [
    { system.stateVersion = 6; }

    # Daily auto-upgrade of this host from github:whexy/dotfiles.
    #
    # NixOS uses system.autoUpgrade (nixos-upgrade.service/.timer); Darwin
    # has no equivalent, so we install a root launchd daemon that runs the
    # same command:
    #   darwin-rebuild switch --refresh --flake github:whexy/dotfiles#<configuration>
    #
    # StartCalendarInterval behaves like the NixOS timer's `persistent = true`:
    # launchd coalesces missed runs into a single job on the next wake, unlike
    # cron which drops them.
    (lib.mkIf cfg.autoUpgrade.enable {
      launchd.daemons.dotfiles-auto-upgrade = {
        script = ''
          # Randomize the 04:00 run by up to 45 minutes (matching the NixOS
          # timer's randomizedDelaySec) so all hosts don't build at once.
          sleep $((RANDOM % 2700))

          exec ${lib.getExe config.system.build.darwin-rebuild} switch \
            --refresh \
            --flake github:whexy/dotfiles#${cfg.autoUpgrade.configuration}
        '';

        serviceConfig = {
          StartCalendarInterval = [
            {
              Hour = 4;
              Minute = 0;
            }
          ];

          StandardOutPath = "/var/log/dotfiles-auto-upgrade.log";
          StandardErrorPath = "/var/log/dotfiles-auto-upgrade.log";
          ProcessType = "Background";
        };
      };
    })
  ];
}
