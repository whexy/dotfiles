# Ghostty terminal configuration
{
  pkgs,
  lib,
  darwin,
  ...
}:
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
      keybind =
        lib.optionals (!darwin) [
          "ctrl+shift+zero=set_font_size:23"
        ]
        ++ lib.optionals darwin [
          "alt+left=unbind"
          "alt+right=unbind"
          "cmd+shift+zero=set_font_size:23"
        ];
    }
    // {
      window-decoration = if darwin then "auto" else "none";
    };
  };
}
