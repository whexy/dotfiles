# Personal workstation home-manager configuration
{ pkgs, lib, ... }:
{
  imports = [
    ./gui/clipboard.nix
    ./gui/git.nix
    ./gui/ghostty.nix
    ./gui/niri.nix
    ./gui/waybar.nix
    ./gui/wezterm.nix
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
