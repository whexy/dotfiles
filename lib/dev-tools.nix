{ inputs, flake }:
system:
let
  # NixOS channels do not wait for Darwin binaries before advancing.
  nixpkgs =
    if inputs.nixpkgs.lib.hasSuffix "-darwin" system then inputs.nixpkgs-darwin else inputs.nixpkgs;
  pkgs = import nixpkgs { inherit system; };
  treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ../treefmt.nix;
  # The flake's lib runner closes over its own nixpkgs, including hook defaults.
  gitHooks = import (inputs.git-hooks + "/nix") {
    inherit nixpkgs system;
    isFlakes = true;
  };
in
{
  inherit pkgs treefmtEval;
  preCommit = gitHooks.run {
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
  };
}
