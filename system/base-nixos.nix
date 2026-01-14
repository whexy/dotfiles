# Base NixOS system configuration
{ lib, wsl, ... }:
lib.mkIf (!wsl) {
  # enable envFS (shabang)
  # disable envFS for WSL, because Windows expect /bin/mount exists
  services.envfs.enable = true;
}
