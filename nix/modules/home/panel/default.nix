# Panel group: waybar and its pills.
{ inputs, lib, ... }:
{
  options.dotfiles.panel = {
    waybar.enable = lib.mkEnableOption "waybar";
    renpho.enable = lib.mkEnableOption "Renpho smart-scale waybar pill";
  };

  imports = [
    inputs.renpho-health.homeModules.default
    inputs.renpho-health.homeModules.waybar
    ./waybar.nix
    ./renpho.nix
  ];
}
