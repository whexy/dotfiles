# Dev Darwin system configuration
{ pkgs, ... }:
{
  time.timeZone = "America/Chicago";
  programs.fish.enable = true;
  environment.shells = with pkgs; [
    bash
    fish
    zsh
  ];
}
