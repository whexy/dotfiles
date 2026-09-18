# Go: toolchain, language server, and linter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.go.enable {
    home.packages = with pkgs; [
      go
    ];

    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
          go
          gomod
          gosum
          gowork
        ];
      lsp.servers.gopls = {
        enable = true;
        config.settings.gopls = {
          gofumpt = true;
          usePlaceholders = true;
          completeUnimported = true;
          staticcheck = true;
          semanticTokens = true;
          analyses = {
            nilness = true;
            unusedparams = true;
            unusedwrite = true;
            useany = true;
          };
          hints = {
            assignVariableTypes = true;
            compositeLiteralFields = true;
            compositeLiteralTypes = true;
            constantValues = true;
            functionTypeParameters = true;
            parameterNames = true;
            rangeVariableTypes = true;
          };
        };
      };
      plugins.lint.lintersByFt.go = [ "golangcilint" ];
    };
  };
}
