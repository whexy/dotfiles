# VirtualBox desktop image settings.
{ lib, ... }:
{
  options.dotfiles.image.virtualbox.enable = lib.mkEnableOption "a VirtualBox desktop image";
}
