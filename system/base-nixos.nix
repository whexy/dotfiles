# Base NixOS system configuration
{ lib, wsl, ... }:
{
  # Enable zsh at system level (required for user shell)
  programs.zsh.enable = true;

  # enable envFS (shabang)
  # disable envFS for WSL, because Windows expect /bin/mount exists
  services.envfs.enable = lib.mkIf (!wsl) true;
}
