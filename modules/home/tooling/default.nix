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
          Clusters to install, each the 1Password document `kube-<name>`
          (modules/home/onepassword/items.nix). The kubeconfig must name its
          cluster, user, and context `<name>`, and its user must hold a
          client certificate.
        '';
      };
    };
    appStoreConnect.enable = lib.mkEnableOption "asc, the App Store Connect CLI, with my API key";
    aws.enable = lib.mkEnableOption "AWS CLI with my credentials from 1Password";
    cloudflare = {
      cli.enable = lib.mkEnableOption "cf, the Cloudflare CLI, and its agent skill";
      apiToken.enable = lib.mkEnableOption "my scoped Cloudflare API token for cf, read from 1Password";
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
    ./app-store-connect/default.nix
    ./aws.nix
    ./cli.nix
    ./cloudflare/default.nix
    ./debug.nix
    ./extras.nix
    ./kube.nix
    ./network.nix
    ./woodpecker.nix
  ];
}
