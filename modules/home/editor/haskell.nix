# Haskell: compiler, build tool, language server, and editor integration.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "haskell" {
    packages = with pkgs; [
      cabal-install
      ghc
    ];
    grammars = [ "haskell" ];
    nixvim.lsp.servers.hls = {
      enable = true;
    };
  };
}
