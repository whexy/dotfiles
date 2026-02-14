# Personal workstation home-manager configuration
{ ... }:
{
  imports = [
    ./gui/clipboard.nix
    ./gui/ghostty.nix
    ./gui/neovide.nix
    ./gui/niri.nix
    ./gui/waybar.nix
    ./gui/wezterm.nix
  ];
}
