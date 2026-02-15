# Personal workstation home-manager configuration
{ ... }:
{
  imports = [
    ./gui/clipboard.nix
    ./gui/git.nix
    ./gui/ghostty.nix
    ./gui/niri.nix
    ./gui/waybar.nix
    ./gui/wezterm.nix
  ];
}
