# Dev Darwin system configuration
{ pkgs, ... }:
{
  time.timeZone = "America/Chicago";
  programs.zsh.enable = true;
  environment.shells = with pkgs; [
    bash
    zsh
  ];
}
