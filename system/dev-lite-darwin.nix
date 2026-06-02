# Dev-lite Darwin system configuration
{ lib, ... }:
{
  time.timeZone = "America/Chicago";
  services.tailscale.enable = true;

  nix = {
    optimise.automatic = true;
    settings.auto-optimise-store = true;
  };
}
