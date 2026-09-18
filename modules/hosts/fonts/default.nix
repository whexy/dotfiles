# Fonts group: desktop fonts and fontconfig defaults.
{ lib, ... }:
{
  options.dotfiles.fonts = {
    enable = lib.mkEnableOption "desktop fonts (Nerd Fonts, Noto CJK)";
  };
}
