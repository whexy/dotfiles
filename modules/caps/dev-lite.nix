# dev-lite cap preset: lightweight development setup (no heavy services).
{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  dotfiles = {
    system = {
      timezone.enable = lib.mkDefault true;
      # Xcodes ships as a Homebrew cask, so the option is inert off Darwin.
      xcodes.enable = lib.mkDefault isDarwin;
    };
    nix.optimise.enable = lib.mkDefault true;
    security.agentPolicy.enable = lib.mkDefault true;
    security.onepassword.enable = lib.mkDefault true;
    network.tailscale = {
      enable = lib.mkDefault true;
      # The home T3 Code server publishes itself with `tailscale serve`.
      userOperator = lib.mkDefault true;
      ssh.enable = lib.mkDefault true;
    };
    homebrew.enable = lib.mkDefault true;
    shell.nushell.enable = lib.mkDefault true;
    monitoring = {
      nodeExporter.enable = lib.mkDefault true;
      beszel.enable = lib.mkDefault true;
    };
  };
}
