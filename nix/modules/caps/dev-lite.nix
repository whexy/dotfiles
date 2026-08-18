# dev-lite cap preset: lightweight development setup (no heavy services).
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
    system.timezone.enable = lib.mkDefault true;
    nix.optimise.enable = lib.mkDefault true;
    security.onepassword.enable = lib.mkDefault true;
    network.tailscale.enable = lib.mkDefault true;
    monitoring = {
      nodeExporter.enable = lib.mkDefault true;
      beszel.enable = lib.mkDefault true;
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
