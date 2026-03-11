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
  ]
  ++ lib.optionals (!darwin) [
    # Linux system use Niri as WM
    ./gui/niri.nix
    ./gui/firefox.nix
    ./gui/obs.nix
  ]
  ++ lib.optionals darwin [
    # MacOS system enable aerospace for WM-like experience
    ./gui/aerospace.nix
    ./gui/karabiner.nix
  ];

  home.packages = lib.optionals (pkgs.stdenv.hostPlatform.isx86_64 && !darwin) [
    pkgs.zoom-us
  ];
}
