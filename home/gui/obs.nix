{ pkgs, ... }:
{
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-websocket
      obs-vaapi # VA-API hardware encoder (AMD/Intel)
    ];
  };
}
