# GUI systems home-manager configuration
{
  lib,
  darwin ? false,
  ...
}:
{
  imports = [
    ./gui/clipboard.nix
    ./gui/git.nix
    ./gui/ghostty.nix
    ./gui/waybar.nix
    ./gui/wezterm.nix
  ]
  ++ lib.optionals (!darwin) [
    # Linux system use Niri as WM
    ./gui/niri.nix
  ]
  ++ lib.optionals darwin [
    # MacOS system enable aerospace for WM-like experience
    ./gui/aerospace.nix
  ];
}
