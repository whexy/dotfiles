# System Darwin configuration: nix-darwin state version, auto-upgrade, and
# Xcodes.
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
  upgrader = import ../../../packages/dotfiles-upgraded/args.nix {
    inherit lib;
    fleet = flake.lib;
    package = perSystem.self.dotfiles-upgraded;
    mode = "darwin";
    # launchd starts the system's current entrypoint again after each switch
    # (the signed launcher in darwin-launcher).
    modeFlags = [ "--exit-after-switch" ];
    cfg = cfg.autoUpgrade;
    ageSecrets = config.age.secrets;
  };
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
    exec ${lib.escapeShellArgs upgrader.argv}
  '';
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.xcodes.enable { homebrew.casks = [ "xcodes-app" ]; })

    (lib.mkIf cfg.autoUpgrade.enable {
      environment.systemPackages = [ service ];

      age.secrets = upgrader.secrets;

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
