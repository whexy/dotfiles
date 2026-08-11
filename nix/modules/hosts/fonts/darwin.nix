# Fonts Darwin configuration: font packages.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.fonts;
in
{
  config = lib.mkIf cfg.enable {
    fonts.packages = [
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
    ];
  };
}
