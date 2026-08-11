# Streaming NixOS configuration: OBS Studio with virtual camera support.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.streaming;
in
{
  config = lib.mkIf cfg.enable {
    programs.obs-studio = {
      enable = true;
      enableVirtualCamera = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-websocket
        obs-vaapi # VA-API hardware encoder (AMD/Intel)
      ];
    };
  };
}
