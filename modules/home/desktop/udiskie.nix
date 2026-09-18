# Automount daemon for removable media using UDisks2 (Linux only).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop;
in
{
  config = lib.mkIf (cfg.udiskie.enable && pkgs.stdenv.hostPlatform.isLinux) {
    services.udiskie = {
      enable = true;
      automount = true;
      notify = true;
      tray = "auto";
    };

    xsession.preferStatusNotifierItems = true;
  };
}
