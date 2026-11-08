# pyelftools at the version REA's pwntools profile names. REA checks the
# exact profile it was verified against (`PROFILE` in its bridge/pwntools)
# and refuses others.
{ pkgs }:
pkgs.python3.pkgs.pyelftools.overridePythonAttrs (old: {
  version = "0.33";
  src = old.src.override {
    tag = "v0.33";
    hash = "sha256-NqF5A6PRl4uncwNS9j44fIV7ovlljiucvV2Msv0LK/w=";
  };
  passthru = old.passthru or { } // {
    # Moves only with the profile of a new rea-agents release.
    updater = null;
  };
})
