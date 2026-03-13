# Ghostty terminal configuration
{ pkgs, darwin, ... }:
let
  p = pkgs.unstable;
  ghostty-pkg = if darwin then p.ghostty-bin else p.ghostty;
in
{
  programs.ghostty = {
    enable = true;
    package = ghostty-pkg;

    settings = {
      theme = "Gruvbox Dark";
      font-size = 14;
      font-family = "FiraCode Nerd Font";
      background-opacity = 0.95;
      background-blur = true;
      window-width = 160;
      window-height = 48;
      window-position-x = 320;
      window-position-y = 144;
      macos-option-as-alt = "left";
      keybind = [
        "alt+left=unbind"
        "alt+right=unbind"
      ];
    };
  };
}
