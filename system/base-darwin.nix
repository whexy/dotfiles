# Base Darwin system configuration
{ pkgs, ... }:
{
  # Enable zsh at system level (required for user shell)
  programs.zsh.enable = true;
  environment.shells = with pkgs; [
    bash
    zsh
  ];

  environment.defaultPackages = with pkgs; [
    nh
  ];
}
