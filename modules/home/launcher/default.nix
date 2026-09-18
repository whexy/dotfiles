# Launcher group: desktop command palette / application launcher.
{ lib, ... }:
{
  options.dotfiles.launcher = {
    vicinae.enable = lib.mkEnableOption "the Vicinae launcher (Linux)";
  };

  imports = [
    ./vicinae.nix
  ];
}
