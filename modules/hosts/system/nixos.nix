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
    # Auto-upgrade of this host from the upstream repo, via the dotfiles-upgraded
    # daemon (packages/dotfiles-upgraded).
    # It replaces the stock nixos-upgrade.timer rather than joining it: two
    # concurrent rebuilds would contend on the Nix store lock.
    (lib.mkIf cfg.autoUpgrade.enable {
      systemd.services.dotfiles-upgraded = {
        description = "Auto-upgrade this host from ${flake.lib.upstreamRef}";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        # Activation would otherwise restart the daemon that started it, killing
        # the rebuild that is switching this very unit. nixos-rebuild insulates
        # switch-to-configuration with `systemd-run --collect`, so activation
        # itself survives; the daemon still records its own result only if it
        # outlives the switch.
        restartIfChanged = false;

        # Mirrors the path nixos-upgrade.service gets: nixos-rebuild shells out
        # to git for the flake fetch and to tar/xz/gzip for substituted paths.
        path = [
          pkgs.coreutils
          pkgs.gnutar
          pkgs.xz.bin
          pkgs.gzip
          pkgs.gitMinimal
          config.nix.package.out
          config.programs.ssh.package
          config.system.build.nixos-rebuild
        ];

        environment =
          config.nix.envVars
          // {
            inherit (config.environment.sessionVariables) NIX_PATH;
            HOME = "/root";

            # Throttles only this daemon's builds; the settings reach the
            # nix-daemon over the socket, which is what actually schedules
            # them (a cgroup limit on this unit would bound the supervisor
            # instead). systemd turns the \n into a real newline.
            NIX_CONFIG = "max-jobs = ${toString cfg.autoUpgrade.maxJobs}\ncores = ${toString cfg.autoUpgrade.cores}";
          }
          // config.networking.proxy.envVars;

        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            (lib.getExe perSystem.self.dotfiles-upgraded)
            "--mode=nixos"
            "--configuration=${cfg.autoUpgrade.configuration}"
            "--flake=${flake.lib.upstreamRef}"
            "--state-dir=/var/lib/dotfiles-upgraded"
            "--poll-interval=${cfg.autoUpgrade.pollInterval}"
            "--max-attempts=${toString cfg.autoUpgrade.maxAttempts}"
            "--require-ci-pass=${lib.boolToString cfg.autoUpgrade.requireCiPass}"
          ];
          Restart = "always";
          RestartSec = 30;
          StateDirectory = "dotfiles-upgraded";
        };
      };
    })

    (lib.mkIf cfg.docs.enable { documentation.dev.enable = true; })

    (lib.mkIf cfg.fwupd.enable { services.fwupd.enable = true; })
  ];
}
