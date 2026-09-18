# System Darwin configuration: nix-darwin state version and auto-upgrade.
{
  config,
  flake,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.system;
in
{
  config = lib.mkMerge [
    { system.stateVersion = 6; }

    # Auto-upgrade of this host from the upstream repo, via the dotfiles-upgraded
    # daemon (packages/dotfiles-upgraded, docs/design/auto-upgrade-daemon.md).
    # The daemon schedules and jitters internally, so launchd only has to keep
    # it alive; the calendar-interval job and its `sleep $((RANDOM % 2700))`
    # jitter it needed are gone.
    (lib.mkIf cfg.autoUpgrade.enable {
      launchd.daemons.dotfiles-upgraded = {
        script = ''
          exec ${lib.getExe perSystem.self.dotfiles-upgraded} \
            --mode=darwin \
            --configuration=${lib.escapeShellArg cfg.autoUpgrade.configuration} \
            --flake=${lib.escapeShellArg flake.lib.upstreamRef} \
            --state-dir=/var/lib/dotfiles-upgraded \
            --poll-interval=${lib.escapeShellArg cfg.autoUpgrade.pollInterval} \
            --max-attempts=${toString cfg.autoUpgrade.maxAttempts} \
            --require-ci-pass=${lib.boolToString cfg.autoUpgrade.requireCiPass}
        '';

        # darwin-rebuild shells out to nix and git, and launchd daemons start
        # with a minimal PATH that contains neither.
        environment.PATH = "${
          lib.makeBinPath [
            pkgs.gitMinimal
            config.nix.package
            config.system.build.darwin-rebuild
          ]
        }:/usr/bin:/bin";

        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;

          StandardOutPath = "/var/log/dotfiles-upgraded.log";
          StandardErrorPath = "/var/log/dotfiles-upgraded.log";
          ProcessType = "Background";
        };
      };
    })
  ];
}
