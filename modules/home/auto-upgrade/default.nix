# Auto-upgrade of a standalone Home Manager setup (non-NixOS hosts) from the
# upstream repo, via the dotfiles-upgraded daemon running as a long-lived user
# service (packages/dotfiles-upgraded).
#
# The daemon polls upstream, waits for CI to pass on the new commit, and then
# runs the same command documented for manual use, plus --refresh:
#   nh home switch <upstreamRef>/<sha> --refresh --no-nom -c <user>@<host> -b backup
#
# The <user>@<host> configuration name is deduced from the path of the
# home-configuration.nix that enabled this module (blueprint names the
# flake output after hosts/<host>/users/<user> but doesn't pass the host
# name into the module; the real machine hostname may differ).
#
# NOTE: on headless servers the user manager stops when you log out, which
# takes this daemon down with it and silently strands the host on its current
# generation. A long-running service depends on lingering more than the timer
# it replaces did, since there is no later catch-up run. Enable it once,
# manually, per host:
#   sudo loginctl enable-linger <user>
# Confirm with `loginctl show-user <user> -p Linger` and check convergence in
# "$XDG_STATE_HOME/dotfiles-upgraded/status.json".
{
  config,
  flake,
  options,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.autoUpgrade;
  inherit (flake.lib) upstreamRef;

  # Find the file that set dotfiles.autoUpgrade.enable = true and parse
  # "<user>@<host>" out of its path:
  #   hosts/<host>/users/<user>/home-configuration.nix
  enablingDef = lib.findFirst (def: (def.value or false) == true) null (
    options.dotfiles.autoUpgrade.enable.definitionsWithLocations or [ ]
  );
  pathMatch =
    if enablingDef != null then
      builtins.match ".*/hosts/([^/]+)/users/([^/]+)/home-configuration\\.nix" (toString enablingDef.file)
    else
      null;

  configuration =
    if cfg.configuration != null then
      cfg.configuration
    else if pathMatch != null then
      "${lib.elemAt pathMatch 1}@${lib.elemAt pathMatch 0}"
    else
      throw ''
        dotfiles.autoUpgrade: could not deduce the configuration name from
        the enabling file's path (expected hosts/<host>/users/<user>/home-configuration.nix).
        Set dotfiles.autoUpgrade.configuration explicitly.
      '';
in
{
  options.dotfiles.autoUpgrade = {
    enable = lib.mkEnableOption "the dotfiles-upgraded daemon, which switches this Home Manager configuration to each upstream commit that passes CI";

    configuration = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The homeConfigurations."<user>@<host>" output of the upstream repo
        to switch to. When null, the name is deduced from the path of the
        home-configuration.nix that enabled this module
        (hosts/<host>/users/<user>). Set explicitly only if the file does
        not follow that layout.
      '';
      example = "wenxuan@mars";
    };

    pollInterval = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = ''
        Base interval between upstream ref checks, as a Go duration. The
        daemon jitters each tick so the fleet does not poll in lockstep,
        and raises the floor when GitHub asks it to.
      '';
      example = "30m";
    };

    maxAttempts = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Switch attempts, with exponential backoff, before the daemon gives
        up on a commit and waits for a newer one. A transient fault and a
        genuinely broken commit are indistinguishable by exit code, so
        retrying lets transients heal without blocking later commits.
      '';
    };

    requireCiPass = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Only switch to commits whose GitHub commit status is success.
        Disabling this removes the only gate on what reaches this host.
      '';
    };

    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = ''
        Derivations the daemon's rebuild may build concurrently
        (Nix's max-jobs). Unattended builds land at arbitrary times, so
        they are throttled below the machine's capacity to leave room for
        whatever else the host is doing; a manual `nh home switch` is
        unaffected and still uses the system-wide default.
      '';
    };

    cores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = ''
        Cores offered to each individual derivation the daemon builds
        (Nix's cores, i.e. $NIX_BUILD_CORES). Peak load is roughly
        maxJobs * cores, since a parallel build takes both.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.dotfiles-upgraded = {
      Unit = {
        Description = "Auto-upgrade Home Manager from ${upstreamRef}";
        # A switch performed by this daemon would otherwise restart the daemon
        # mid-`nh`, killing the switch it is running. Unlike nixos-rebuild,
        # nothing here insulates activation from the calling unit, so the new
        # version is only picked up on the next manual restart or login.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "simple";
        # nh shells out to nix; the user manager on generic-Linux hosts does
        # not inherit the login PATH. Include the standard profile locations
        # as a fallback when no nix.package is selected for the user.
        Environment = [
          "PATH=${
            lib.makeBinPath (
              [
                pkgs.git
                pkgs.nh
              ]
              ++ lib.optional (config.nix.package != null) config.nix.package
            )
          }:${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"

          # Throttles only this daemon's builds; the settings reach the
          # nix-daemon over the socket, which is what actually schedules
          # them. Home Manager renders this list into the unit verbatim, so
          # the separator is the literal two-character escape that systemd
          # expands into a newline, not a real one (which would split the
          # Environment= line and break the unit).
          ''NIX_CONFIG=max-jobs = ${toString cfg.maxJobs}\ncores = ${toString cfg.cores}''
        ];
        ExecStart = lib.escapeShellArgs [
          (lib.getExe perSystem.self.dotfiles-upgraded)
          "--mode=home-manager"
          "--configuration=${configuration}"
          "--flake=${upstreamRef}"
          "--state-dir=${config.xdg.stateHome}/dotfiles-upgraded"
          "--poll-interval=${cfg.pollInterval}"
          "--max-attempts=${toString cfg.maxAttempts}"
          "--require-ci-pass=${lib.boolToString cfg.requireCiPass}"
        ];
        Restart = "always";
        RestartSec = 30;
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
