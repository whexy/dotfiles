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

  home.packages =
    with pkgs;
    lib.optionals (!darwin) [
      # Linux only
      obsidian
      nautilus # required by xdg-desktop-portal-gnome for FileChooser
    ]
    ++ lib.optionals (!darwin && pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
      # x86-64 Linux only
      zoom-us
    ];
}
