# Tooling group: development CLI package bundles. Each bundle is gated by
# its own option so capability presets (dev, dev-lite) compose exactly the
# set they need. Language toolchains, LSPs, and formatters live in the
# `editor` group as per-language bundles (`editor.<language>.enable`).
{ lib, ... }:
{
  options.dotfiles.tooling = {
    cli.enable = lib.mkEnableOption "everyday CLI tools";
    network.enable = lib.mkEnableOption "network diagnostic tools";
    extras.enable = lib.mkEnableOption "extra dev utilities";
    debug.enable = lib.mkEnableOption "Linux tracing, profiling, and fuzzing tools";
    kube = {
      enable = lib.mkEnableOption "kubeconfigs for my clusters, merged for kubectx";
      clusters = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "clusters-work" ];
        description = ''
          Clusters to install, each read from `secrets/kube-<name>.age`. The
          kubeconfig must name its cluster, user, and context `<name>`.
        '';
      };
    };
    woodpecker = {
      enable = lib.mkEnableOption "woodpecker-cli preconfigured against my CI server";
      server = lib.mkOption {
        type = lib.types.str;
        default = "https://make.clusters.work";
        description = "Woodpecker server URL passed as WOODPECKER_SERVER.";
      };
    };
  };

  imports = [
    ./cli.nix
    ./debug.nix
    ./extras.nix
    ./kube.nix
    ./network.nix
    ./woodpecker.nix
  ];
}
