{ config, lib, ... }:
let
  cfg = config.dotfiles.nix;
in
{
  config = lib.mkIf cfg.gc.enable {
    nix.gc = {
      dates = "weekly";
      randomizedDelaySec = "2h";
    };
  };
}
