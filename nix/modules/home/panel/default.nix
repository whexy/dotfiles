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

  imports = [
    ./waybar.nix
    ./eww.nix
    ./sketchybar.nix
    ./renpho
    ./wm
    ./ai-quota
  ];
}
