# Panel group: Waybar on Linux, SketchyBar on macOS, and their pills.
{ inputs, lib, ... }:
{
  options.dotfiles.panel = {
    waybar.enable = lib.mkEnableOption "Waybar status bar (Linux)";
    sketchybar.enable = lib.mkEnableOption "SketchyBar status bar (macOS)";
    renpho.enable = lib.mkEnableOption "Renpho smart-scale Waybar pill";
  };

  imports = [
    inputs.renpho-health.homeModules.default
    inputs.renpho-health.homeModules.waybar
    ./waybar.nix
    ./sketchybar.nix
    ./renpho.nix
  ];
}
