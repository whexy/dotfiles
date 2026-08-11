# Browser group: Firefox system integration.
# Mirrors the home browser group (profile management).
{ lib, ... }:
{
  options.dotfiles.browser = {
    firefox.enable = lib.mkEnableOption "Firefox";
  };
}
