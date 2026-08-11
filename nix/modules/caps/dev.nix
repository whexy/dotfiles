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
      timezone.enable = true;
      docs.enable = true;
    };
    nix = {
      optimise.enable = true;
      linuxBuilder.enable = true;
    };
    compat = {
      nix-ld.enable = true;
      binfmt.enable = true;
    };
    security = {
      onepassword.enable = true;
      passwordlessSudo.enable = true;
    };
    network = {
      tailscale.enable = true;
      basics.enable = true;
    };
    services.openssh.enable = true;
    monitoring.nodeExporter.enable = true;
    virtualization = {
      docker = {
        enable = true;
        gvisor = true;
      };
      podman.enable = true;
      incus.enable = true;
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
