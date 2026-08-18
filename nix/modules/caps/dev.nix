# dev cap preset: machines used for development.
#
# Options whose config only exists on one platform (e.g. virtualization on
# NixOS, nix.linuxBuilder on Darwin) are no-ops elsewhere, so one preset
# file serves both platforms.
{
  config,
  flake,
  lib,
  ...
}:
let
  isDarwin = lib.hasSuffix "-darwin" config.dotfiles.host.system;
in
{
  dotfiles = {
    system = {
      timezone.enable = lib.mkDefault true;
      docs.enable = lib.mkDefault true;
    };
    nix = {
      optimise.enable = lib.mkDefault true;
      linuxBuilder.enable = lib.mkDefault true;
    };
    compat = {
      nix-ld.enable = lib.mkDefault true;
      binfmt.enable = lib.mkDefault true;
    };
    security = {
      onepassword.enable = lib.mkDefault true;
      passwordlessSudo.enable = lib.mkDefault true;
    };
    network = {
      tailscale.enable = lib.mkDefault true;
      networkmanager.enable = lib.mkDefault true;
    };
    services.openssh.enable = lib.mkDefault true;
    monitoring = {
      nodeExporter.enable = lib.mkDefault true;
      beszel = {
        enable = lib.mkDefault true;
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBlZA5rswnKHS8M8ZMxqTxlJ8FM0Y9Pt9jrt52kGfC3m";
        hubUrl = "https://beszel.at-basking.ts.net";
      };
    };
    virtualization = {
      docker = {
        enable = lib.mkDefault true;
        gvisor = lib.mkDefault true;
      };
      podman.enable = lib.mkDefault true;
      incus.enable = lib.mkDefault true;
    };
  };

  nixpkgs.overlays =
    # Note: pkgs.stdenv cannot be used here (pkgs depends on overlays).
    [ flake.lib.overlays.llm-tools ]
    ++ lib.optionals isDarwin [
      flake.lib.overlays.container-darwin
      flake.lib.overlays.direnv-darwin
    ];
}
