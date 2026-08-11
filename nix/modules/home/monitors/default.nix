# Monitors group: CLI system monitors.
{ lib, ... }:
{
  options.dotfiles.monitors = {
    htop.enable = lib.mkEnableOption "htop";
    btop.enable = lib.mkEnableOption "btop";
  };

  imports = [
    ./htop.nix
    ./btop.nix
  ];
}
