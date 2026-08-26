# Renpho smart-scale data integration shared by Waybar and SketchyBar.
#
# The renpho-health input owns data fetching, cache refresh, and the query CLI.
# This panel module owns all status-bar rendering.
{ config, lib, ... }:
{
  config = lib.mkIf config.dotfiles.panel.renpho.enable {
    age.secrets.renpho-creds.file = ../../../../../secrets/renpho-creds.age;

    services.renpho-health = {
      enable = true;
      credsFile = config.age.secrets.renpho-creds.path;
    };
  };

  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
  ];
}
