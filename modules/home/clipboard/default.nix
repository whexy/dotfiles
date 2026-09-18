# Clipboard group: clipboard history and host<->guest integration.
{ lib, ... }:
{
  options.dotfiles.clipboard = {
    history.enable = lib.mkEnableOption "Wayland clipboard persistence and history";
    vmware.enable = lib.mkEnableOption "VMware host<->guest clipboard integration";
  };

  imports = [
    ./clipboard.nix
    ./vmware.nix
  ];
}
