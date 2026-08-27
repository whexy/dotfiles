# Fonts Darwin configuration: font packages.
{
  config,
  pkgs,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.fonts;
in
{
  config = lib.mkIf cfg.enable {
    fonts.packages = [
      perSystem.self.perfect-dos-vga-437-nerd-font
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
    ];
  };
}
