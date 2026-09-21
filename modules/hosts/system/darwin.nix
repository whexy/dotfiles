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
  service = pkgs.writeShellScriptBin "dotfiles-upgraded-service" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.gitMinimal
        config.nix.package
        config.system.build.darwin-rebuild
      ]
    }:/usr/bin:/bin:/usr/sbin:/sbin
    export HOME=/var/root
    # Throttles only this daemon's builds; the settings reach the nix-daemon
    # over the socket, which is what actually schedules them.
    export NIX_CONFIG=$'max-jobs = ${toString cfg.autoUpgrade.maxJobs}\ncores = ${toString cfg.autoUpgrade.cores}'
    exec ${lib.getExe perSystem.self.dotfiles-upgraded} \
      --mode=darwin \
      --exit-after-switch \
      --configuration=${lib.escapeShellArg cfg.autoUpgrade.configuration} \
      --flake=${lib.escapeShellArg flake.lib.upstreamRef} \
      --state-dir=/var/lib/dotfiles-upgraded \
      --poll-interval=${lib.escapeShellArg cfg.autoUpgrade.pollInterval} \
      --max-attempts=${toString cfg.autoUpgrade.maxAttempts} \
      --require-ci-pass=${lib.boolToString cfg.autoUpgrade.requireCiPass}
  '';
in
{
  config = lib.mkMerge [
    { system.stateVersion = 6; }

    (lib.mkIf cfg.autoUpgrade.enable {
      environment.systemPackages = [ service ];

      # No store paths in this plist: changing it during activation would
      # unload the daemon and kill the switch it is supervising. The signed
      # launcher reloads the current system's entrypoint after each success.
      launchd.daemons.dotfiles-upgraded.serviceConfig = {
        ProgramArguments = [
          "/Applications/Dotfiles Updater.app/Contents/MacOS/dotfiles-updater-launcher"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/var/log/dotfiles-upgraded.log";
        StandardErrorPath = "/var/log/dotfiles-upgraded.log";
        ProcessType = "Background";
        ExitTimeOut = 30;
      };
    })
  ];
}
