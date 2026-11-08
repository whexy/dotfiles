# The daemon's options, declared alike by the system group
# (dotfiles.system.autoUpgrade) and the home (dotfiles.autoUpgrade). A plain
# function: each caller supplies the options that differ, the configuration
# it switches to and where the daemon keeps its state.
{
  lib,
  # "host" or "home", what the daemon switches.
  subject,
  configuration,
  stateDir,
  # How the announcement relay is reached, completing a sentence.
  relayRoute ? "is on the tailnet",
}:
{
  enable = lib.mkEnableOption "the dotfiles-upgraded daemon, which switches this ${subject} to each upstream commit that passes CI";

  inherit configuration stateDir;

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
        (flake.lib.rollout), so the ${subject} switches as soon as CI passes and
        asks GitHub only every `notify.pollInterval`. The relay ${relayRoute};
        while it cannot be reached, the daemon polls GitHub every
        `pollInterval`, as it does without this.
      '';
    };

    pollInterval = lib.mkOption {
      type = lib.types.str;
      default = "6h";
      description = ''
        Base interval between upstream ref checks while the announcement
        stream is up, as a Go duration. GitHub is then only the fallback
        for an announcement the ${subject} missed.
      '';
    };
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
      Disabling this removes the only gate on what reaches this ${subject}.
    '';
  };

  reportFailures = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Post each commit the daemon gives up switching to, with the end of
      the rebuild output, to the fleet's failure webhook
      (flake.lib.upgradeFailureWebhook), which opens a GitHub issue for
      the commit or adds this ${subject} to the open one.
    '';
  };

  maxJobs = lib.mkOption {
    type = lib.types.ints.positive;
    default = 2;
    description = ''
      Derivations the daemon's rebuild may build concurrently
      (Nix's max-jobs). Unattended builds land at arbitrary times, so
      they are throttled below the machine's capacity to leave room for
      whatever else the ${subject} is doing; a manual switch is unaffected
      and still uses the system-wide default.
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
}
