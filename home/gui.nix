# GUI systems home-manager configuration
{
  pkgs,
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
  ++ lib.optionals (darwin) [
    # MacOS system enable aerospace for WM-like experience
    ./gui/aerospace.nix
  ];

  # Wayland clipboard tools (Linux only)
  home.packages = lib.optionals pkgs.stdenv.isLinux (
    with pkgs;
    [
      swaybg
      wl-clipboard
    ]
  );

  # Wayland clipboard persistence (Linux only)
  services.wl-clip-persist.enable = lib.mkIf pkgs.stdenv.isLinux true;
}
