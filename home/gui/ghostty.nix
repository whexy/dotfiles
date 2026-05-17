# Ghostty terminal configuration
{ pkgs, darwin, ... }:
let
  ghostty-pkg = if darwin then pkgs.ghostty-bin else pkgs.ghostty;
in
{
  programs.ghostty = {
    enable = true;
    package = ghostty-pkg;

    settings = {
      theme = "Gruvbox Dark";
      font-size = 14;
      font-family = "FiraCode Nerd Font";
      background-opacity = 0.90;
      background-blur = true;
      macos-option-as-alt = "left";
      window-decoration = "none";
      keybind = [
        "alt+left=unbind"
        "alt+right=unbind"
        "ctrl+shift+zero=set_font_size:23"
      ];
    };
  };
}
