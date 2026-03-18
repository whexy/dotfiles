# GUI systems home-manager configuration
{
  lib,
  pkgs,
  darwin ? false,
  ...
}:
{
  imports = [
    ./gui/clipboard.nix
    ./gui/ghostty.nix
    ./gui/git.nix
    ./gui/waybar.nix
    ./gui/wezterm.nix
    ./gui/firefox.nix
  ]
  ++ lib.optionals (!darwin) [
    # Linux system use Niri as WM
    ./gui/niri.nix
    ./gui/obs.nix
    # Input method (fcitx5 + rime)
    ./gui/fcitx5.nix
  ]
  ++ lib.optionals darwin [
    # MacOS system enable aerospace for WM-like experience
    ./gui/aerospace.nix
    ./gui/karabiner.nix
  ];
}
