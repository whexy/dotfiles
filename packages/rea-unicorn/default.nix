# Unicorn at the version REA's pwntools profile names. REA checks the exact
# profile it was verified against (`PROFILE` in its bridge/pwntools) and
# refuses others.
{ pkgs }:
pkgs.unicorn.overrideAttrs (
  finalAttrs: old: {
    version = "2.1.2";
    src = pkgs.fetchFromGitHub {
      owner = "unicorn-engine";
      repo = "unicorn";
      tag = finalAttrs.version;
      hash = "sha256-qA84xBztyWmt/rUExhhZMkQzvDPx0UE9MAIPG/Su3iE=";
    };
    passthru = old.passthru or { } // {
      # Moves only with the profile of a new rea-agents release.
      updater = null;
    };
  }
)
