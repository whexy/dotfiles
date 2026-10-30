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
    # Inert without systemd-boot. Each listed generation keeps its kernel and
    # initrd on the ESP, so under auto-upgrades an uncapped menu fills a
    # 512 MiB ESP, after which switch-to-configuration fails and the host
    # stops converging.
    { boot.loader.systemd-boot.configurationLimit = lib.mkDefault 15; }

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

        # The daemon is usually what runs the switch that changes this unit, so
        # the switch reloads it, and the reload restarts the daemon once that
        # switch has finished (flake.lib.upgraderReload).
        reloadIfChanged = true;

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

            # Caps only the rebuilds this daemon runs; a manual rebuild keeps
            # the system default. systemd turns the \n into a real newline.
            NIX_CONFIG = "max-jobs = ${toString cfg.autoUpgrade.maxJobs}\ncores = ${toString cfg.autoUpgrade.cores}";
          }
          // config.networking.proxy.envVars;

        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            (lib.getExe perSystem.self.dotfiles-upgraded)
            "--mode=nixos"
            "--configuration=${cfg.autoUpgrade.configuration}"
            "--flake=${flake.lib.upstreamRef}"
            "--state-dir=${cfg.autoUpgrade.stateDir}"
            "--poll-interval=${cfg.autoUpgrade.pollInterval}"
            "--max-attempts=${toString cfg.autoUpgrade.maxAttempts}"
            "--require-ci-pass=${lib.boolToString cfg.autoUpgrade.requireCiPass}"
          ];
          ExecReload = flake.lib.upgraderReload {
            systemd = config.systemd.package;
            inherit (pkgs) util-linux;
            inherit (cfg.autoUpgrade) stateDir;
            user = false;
          };
          Restart = "always";
          RestartSec = 30;
          StateDirectory = "dotfiles-upgraded";

          # As root, nixos-rebuild's Nix opens the store directly instead of
          # going through nix-daemon, so evaluation, substitution and every
          # build run in this unit's cgroup; only switch-to-configuration
          # leaves it. A rebuild the OOM killer takes is retried later.
          CPUWeight = 20;
          IOWeight = 20;
          OOMScoreAdjust = 500;
        };
      };
    })

    (lib.mkIf cfg.docs.enable { documentation.dev.enable = true; })

    (lib.mkIf cfg.fwupd.enable { services.fwupd.enable = true; })
  ];
}
