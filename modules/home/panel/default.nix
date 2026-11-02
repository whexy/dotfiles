# Panel group: status bar (Waybar or Eww on Linux, SketchyBar on macOS)
# and their pills.
{ lib, ... }:
{
  options.dotfiles.panel = {
    waybar.enable = lib.mkEnableOption "the Linux status bar";
    linuxBar = lib.mkOption {
      type = lib.types.enum [
        "waybar"
        "eww"
      ];
      default = "waybar";
      description = "Which renderer renders the Linux status bar.";
    };
    sketchybar.enable = lib.mkEnableOption "SketchyBar status bar (macOS)";
    renpho.enable = lib.mkEnableOption "Renpho smart-scale panel pill";
    aiQuota.showCountdown = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to show the reset countdown in AI quota bar pills.";
    };
  };

  # homeModules.all also imports these by file path. The module system keys
  # imports by path string, and ./renpho is not ./renpho/default.nix, so a
  # directory import would load each module twice.
  imports = [
    ./waybar.nix
    ./eww.nix
    ./sketchybar.nix
    ./renpho/default.nix
    ./wm/default.nix
    ./ai-quota/default.nix
  ];
}
