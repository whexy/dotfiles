# Neovide GUI configuration (mirrors Ghostty's look & feel)
{
  lib,
  darwin,
  osConfig ? null,
  ...
}:
let
  macbookScreen = osConfig.hardware.display.macbookScreen or false;
in
{
  programs.neovide = {
    enable = true;
    settings = {
      font = {
        normal = [ "FiraCode Nerd Font" ];
        size = if macbookScreen then 16.0 else 14.0;
      };
      # Same translucency as Ghostty (background-opacity = 0.90)
      transparency = 0.9;
    }
    # Same as Ghostty's background-blur; Neovide only supports blur on macOS
    // lib.optionalAttrs darwin { background-blur-radius = 20; };
  };
}
