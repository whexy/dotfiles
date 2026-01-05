# Ghostty terminal configuration
{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin;

    settings = {
      theme = "Gruvbox Dark";
      font-size = 16;
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
