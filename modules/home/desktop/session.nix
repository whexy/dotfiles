# Wayland session services: the lock screen and the tray applets.
args@{
  config,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.desktop;
  inherit (import ./style.nix) colors font;
in
{
  config = lib.mkIf cfg.session.enable {
    programs.swaylock = {
      enable = true;
      settings = {
        color = lib.removePrefix "#" colors.bg0;
        inherit font;
        indicator-radius = 100;
        show-failed-attempts = true;
      };
    };

    services = {
      blueman-applet.enable = true;
      network-manager-applet.enable = osConfig.dotfiles.network.networkmanager.enable or false;
    };
  };
}
