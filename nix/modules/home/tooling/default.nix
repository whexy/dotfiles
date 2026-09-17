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
    ./network.nix
    ./woodpecker.nix
  ];
}
