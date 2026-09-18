# Window-manager integration for the status bar.
#
# Contributes workspace and focused-window items to sketchybar (macOS,
# AeroSpace or Paneru) and waybar (Linux, niri). The bar renderers stay
# WM-agnostic: these files only use the extension points declared in
# ../sketchybar.nix (items, events) and mkOrder-merged waybar settings.
{
  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
  ];
}
