# GUI NixOS system configuration
{ pkgs, ... }:
{
  fonts.packages = [
    (pkgs.nerd-fonts.fira-code)
    (pkgs.nerd-fonts.jetbrains-mono)
  ];
}
