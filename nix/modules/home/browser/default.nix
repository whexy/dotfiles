# Browser group: Firefox.
{ lib, ... }:
{
  options.dotfiles.browser = {
    firefox.enable = lib.mkEnableOption "Firefox";
  };

  imports = [ ./firefox.nix ];
}
