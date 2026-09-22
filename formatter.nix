{
  inputs,
  flake,
  system,
  ...
}:
(import ./lib/dev-tools.nix { inherit inputs flake; } system).treefmtEval.config.build.wrapper
