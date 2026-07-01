{
  inputs,
  flake,
  pkgs,
  system,
  ...
}:
let
  treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ../treefmt.nix;
in
inputs.git-hooks.lib.${system}.run {
  src = flake;
  hooks = {
    treefmt = {
      enable = true;
      package = treefmtEval.config.build.wrapper;
    };
    statix.enable = true;
    nil.enable = true;
    deadnix.enable = true;
  };
}
