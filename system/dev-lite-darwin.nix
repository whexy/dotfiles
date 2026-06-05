# Dev-lite Darwin system configuration
_: {
  time.timeZone = "America/Chicago";
  services.tailscale.enable = true;

  nix = {
    optimise.automatic = true;
    settings.auto-optimise-store = true;
  };
}
