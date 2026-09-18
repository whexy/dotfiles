# Aggregates every dotfiles home feature module (options + config in each
# <feature>/default.nix). Capability presets (caps/<cap>.nix) are NOT
# imported here — they are imported selectively via flake.lib.homeCapsModules.
{ inputs, flake, ... }:
{
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.nix-index-database.homeModules.default
  ]
  ++ flake.lib.importDir ./. {
    pattern = "default.nix";
    exclude = [ "caps/" ];
  };
}
