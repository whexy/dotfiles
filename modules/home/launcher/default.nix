# Launcher group: desktop command palette / application launcher.
{ lib, ... }:
{
  options.dotfiles.launcher = {
    vicinae.enable = lib.mkEnableOption "the Vicinae launcher (Linux)";
    alfred = {
      enable = lib.mkEnableOption "Alfred workflows from this repository (macOS)";
      workflows = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        description = "Alfred workflows by name, each a directory holding the workflow's info.plist.";
      };
    };
  };

  imports = [
    ./alfred.nix
    ./vicinae.nix
  ];
}
