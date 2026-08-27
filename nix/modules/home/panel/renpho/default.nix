# Renpho smart-scale data integration for the status bars.
#
# Each selected bar invokes the query CLI directly on its own interval.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.dotfiles.panel.renpho.enable {
    age.secrets.renpho-creds.file = ../../../../../secrets/renpho-creds.age;

    home.packages = [ inputs.renpho-health.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  };

  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
  ];
}
