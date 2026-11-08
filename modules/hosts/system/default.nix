# System group: timezone, auto-upgrade, boot menu size, developer
# documentation, Xcode management.
{ config, lib, ... }:
let
  cfg = config.dotfiles.system;
in
{
  options.dotfiles.system = {
    timezone.enable = lib.mkEnableOption "the dotfiles timezone (America/Chicago)";

    autoUpgrade = {
      enable = lib.mkEnableOption "the dotfiles-upgraded daemon, which switches this host to each upstream commit that passes CI";

      configuration = lib.mkOption {
        type = lib.types.str;
        default = config.dotfiles.host.hostName;
        defaultText = "config.dotfiles.host.hostName";
        description = ''
          The nixosConfigurations.<name> (NixOS) or
          darwinConfigurations.<name> (Darwin) output of the upstream repo
          (flake.lib.upstreamRef) to switch to. Override when the flake
          output name differs from the runtime hostname.
        '';
        example = "remote-dev";
      };

      pollInterval = lib.mkOption {
        type = lib.types.str;
        default = "10m";
        description = ''
          Base interval between upstream ref checks while no announcement
          stream is up (`notify`), as a Go duration. The daemon jitters each
          tick so the fleet does not poll in lockstep, and raises the floor
          when GitHub asks it to.
        '';
        example = "30m";
      };

      notify = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Subscribe to CI's signed announcements of commits that pass
            (flake.lib.rollout), so the host switches as soon as CI passes and
            asks GitHub only every `notify.pollInterval`. The relay is on the
            tailnet; while it cannot be reached, the daemon polls GitHub every
            `pollInterval`, as it does without this.
          '';
        };

        pollInterval = lib.mkOption {
          type = lib.types.str;
          default = "6h";
          description = ''
            Base interval between upstream ref checks while the announcement
            stream is up, as a Go duration. GitHub is then only the fallback
            for an announcement the host missed.
          '';
        };
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/dotfiles-upgraded";
        readOnly = true;
        description = ''
          Where the daemon keeps its state and publishes its health signal,
          status.json. Fixed because NixOS's StateDirectory= creates it.
        '';
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

      reportFailures = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Post each commit the daemon gives up switching to, with the end of
          the rebuild output, to the fleet's failure webhook
          (flake.lib.upgradeFailureWebhook), which opens a GitHub issue for
          the commit or adds this host to the open one.
        '';
      };

      maxJobs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = ''
          Derivations the daemon's rebuild may build concurrently
          (Nix's max-jobs). Unattended builds land at arbitrary times, so
          they are throttled below the machine's capacity to leave room
          for whatever else the host is doing; a manual rebuild is
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

    fwupd.enable = lib.mkEnableOption "Linux Vendor firmware service";

    docs.enable = lib.mkEnableOption "developer documentation (man pages for syscalls & libc, sections 2 and 3)";

    xcodes.enable = lib.mkEnableOption "the Xcodes app for installing and switching Xcode versions (macOS)";
  };

  config = lib.mkIf cfg.timezone.enable { time.timeZone = "America/Chicago"; };
}
