{ inputs, pkgs, ... }:
(inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build.wrapper
