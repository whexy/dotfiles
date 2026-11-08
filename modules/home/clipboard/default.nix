# Clipboard group: clipboard history.
{ lib, ... }:
{
  options.dotfiles.clipboard = {
    history.enable = lib.mkEnableOption "Wayland clipboard persistence and history";
  };

  imports = [ ./clipboard.nix ];
}
