# Go: toolchain, language server, and linter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "go" {
    packages = with pkgs; [
      go
    ];
    grammars = [
      "go"
      "gomod"
      "gosum"
      "gowork"
    ];
    nixvim = {
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
