# Base Darwin system configuration
{ flake, pkgs, ... }:
{
  nixpkgs.overlays = [ flake.lib.overlays.unstable ];

  # Enable zsh at system level (required for user shell)
  programs.zsh.enable = true;
  environment.shells = with pkgs; [
    bash
    zsh
  ];
}
