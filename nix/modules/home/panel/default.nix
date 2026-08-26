# Panel group: status bar (Waybar or Eww on Linux, SketchyBar on macOS)
# and their pills.
{ inputs, lib, ... }:
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
  };

  imports = [
    inputs.renpho-health.homeModules.default
    ./waybar.nix
    ./eww.nix
    ./sketchybar.nix
    ./renpho
    ./wm
    ./ai-quota
  ];
}
