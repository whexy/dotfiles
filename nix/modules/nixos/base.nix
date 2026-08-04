# Base NixOS system configuration
{
  flake,
  lib,
  wsl,
  ...
}:
{
  nixpkgs.overlays = [
    flake.lib.overlays.unstable
    flake.lib.overlays.tailscale-security
  ];

  # Enable zsh at system level (required for user shell)
  programs.zsh.enable = true;

  # enable envFS (shabang)
  # disable envFS for WSL, because Windows expect /bin/mount exists
  services.envfs.enable = lib.mkIf (!wsl) true;
}
