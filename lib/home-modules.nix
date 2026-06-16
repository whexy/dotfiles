# Shared home-manager module imports used by both mkhost.nix (integrated HM)
# and mkhome.nix (standalone HM). Any new global HM module should be added here.
#
# Usage:
#   commonHomeModules { inherit inputs root; } { inherit caps; }
#
# `root` must be the flake root path (i.e. `self` or the directory containing flake.nix).
# Returns a list of home-manager module paths/references.
{ inputs, root }:
{ caps }:
[
  inputs.agenix.homeManagerModules.default
  inputs.nix-index-database.homeModules.default

  "${root}/home/modules/programs/rclone.nix"
]
++ inputs.nixpkgs.lib.optionals (builtins.elem "gui" caps) [
  inputs.renpho-health.homeModules.default
  inputs.renpho-health.homeModules.waybar
]
