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
    system.timezone.enable = true;
    nix.optimise.enable = true;
    security.onepassword.enable = true;
    network.tailscale.enable = true;
  };

  nixpkgs.overlays =
    # Note: pkgs.stdenv cannot be used here (pkgs depends on overlays).
    [ flake.lib.overlays.llm-tools ]
    ++ lib.optionals isDarwin [
      flake.lib.overlays.container-darwin
      flake.lib.overlays.direnv-darwin
    ];
}
