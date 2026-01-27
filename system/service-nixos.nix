# Service NixOS system configuration
{ pkgs, ... }:
{
  time.timeZone = "America/Chicago";

  # Service essentials
  networking.networkmanager.enable = true;
  services.openssh.enable = true;
  services.tailscale.enable = true;

  # Docker (without gVisor)
  virtualisation.docker.enable = true;
}
