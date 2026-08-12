# Haskell: compiler, build tool, language server, and editor integration.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.haskell.enable {
    home.packages = with pkgs; [
      cabal-install
      ghc
    ];

    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ haskell ];
      lsp.servers.hls = {
        enable = true;
      };
    };
  };
}
