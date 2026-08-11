{ config, lib, ... }:
let
  cfg = config.dotfiles.gaming;
in
{
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
  };
}
