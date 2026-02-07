# Personal workstation home-manager configuration
{ ... }:
{
  imports = [
    ./gui/ghostty.nix
    ./gui/niri.nix
    ./gui/waybar.nix
    ./gui/wezterm.nix
  ];
}
