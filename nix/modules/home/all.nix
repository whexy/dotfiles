# Aggregates every dotfiles home feature module (options + config in each
# <feature>/default.nix) plus the rclone upstream-module fork. Capability
# presets (caps/<cap>.nix) are NOT imported here — they are imported
# selectively via flake.lib.homeCapsModules.
{ inputs, flake, ... }:
{
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.nix-index-database.homeModules.default
    ./rclone.nix
  ]
  ++ flake.lib.importDir ./. {
    pattern = "default.nix";
    exclude = [ "caps/" ];
  };
}
