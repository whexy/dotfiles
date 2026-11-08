# Home Manager entry point for standalone homes: users on Linux machines this
# repo does not manage as NixOS or Darwin hosts. Each home adds its caps with
# flake.lib.homeCapsModules; without osConfig, the home configures its own
# nixpkgs.
{ flake, ... }:
{
  imports = [ flake.homeModules.all ];

  nixpkgs = {
    config.allowUnfree = true;
    overlays = flake.lib.commonOverlays;
  };

  targets.genericLinux = {
    enable = true;
    gpu.enable = false;
  };
}
