# Compat group: run foreign binaries (envfs shebangs, nix-ld, binfmt emulation).
{ lib, ... }:
{
  options.dotfiles.compat = {
    envfs.enable = lib.mkEnableOption "envfs (FUSE filesystem providing /usr/bin/env shebangs)";
    nix-ld.enable = lib.mkEnableOption "nix-ld (run unpatched dynamic binaries)";
    binfmt.enable = lib.mkEnableOption "binfmt emulation of other Linux platforms";
  };
}
