# dev cap preset: machines used for development; dev-lite plus heavy
# services and toolchains.
#
# Options whose config only exists on one platform (e.g. virtualization on
# NixOS, nix.linuxBuilder on Darwin) are no-ops elsewhere, so one preset
# file serves both platforms.
{ lib, pkgs, ... }:
{
  imports = [ ./dev-lite.nix ];

  dotfiles = {
    system.docs.enable = lib.mkDefault true;
    nix.linuxBuilder.enable = lib.mkDefault true;
    compat = {
      nix-ld.enable = lib.mkDefault true;
      binfmt.enable = lib.mkDefault true;
    };
    security.passwordlessSudo.enable = lib.mkDefault true;
    network = {
      # Rex's login server on the tailnet. On Darwin the Rex app is the
      # server, which the gui cap publishes.
      tailscale.rex.enable = lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) (lib.mkDefault true);
      networkmanager.enable = lib.mkDefault true;
    };
    # Keeps user services such as the T3 Code server up on headless hosts.
    user.linger = lib.mkDefault true;
    services.openssh = {
      enable = lib.mkDefault true;
      hardened = lib.mkDefault true;
    };
    # Agents drive Firefox headlessly. Only has an effect on Darwin, where
    # the browser comes from a Homebrew cask; on NixOS the home browser group
    # installs it.
    browser.firefox.automation.enable = lib.mkDefault true;
    virtualization = {
      docker = {
        enable = lib.mkDefault true;
        gvisor = lib.mkDefault true;
        onDemand = lib.mkDefault true;
        autoPrune = lib.mkDefault true;
      };
      podman.enable = lib.mkDefault true;
      incus = {
        enable = lib.mkDefault true;
        onDemand = lib.mkDefault true;
      };
    };
  };
}
