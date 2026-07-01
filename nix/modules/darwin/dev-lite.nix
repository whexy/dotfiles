# Dev-lite Darwin system configuration
{ flake, ... }:
{
  nixpkgs.overlays = [
    flake.lib.overlays.llm-tools
    flake.lib.overlays.container-darwin
    flake.lib.overlays.direnv-darwin
  ];

  time.timeZone = "America/Chicago";
  programs._1password.enable = true;
  services.tailscale.enable = true;

  nix = {
    optimise.automatic = true;
    settings.auto-optimise-store = true;
  };
}
