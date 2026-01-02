# Minimal system basics for ALL hosts (including headless servers)
{ pkgs, inputs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    (final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (prev) system;
        config = prev.config;
      };
    })
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    jq
    openssh
    podman
    rsync
    vim
    wget
    ghostty-bin.terminfo
  ];
}
