# JavaScript/TypeScript: runtimes and language server.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.javascript.enable {
    home.packages = with pkgs; [
      bun
      deno
      nodejs
    ];

    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
          javascript
          jsdoc
          tsx
          typescript
        ];
      lsp.servers = {
        vtsls = {
          enable = true;
          config.settings = {
            typescript = {
              inlayHints = {
                parameterNames.enabled = "literals";
                parameterTypes.enabled = true;
                variableTypes.enabled = true;
                propertyDeclarationTypes.enabled = true;
                functionLikeReturnTypes.enabled = true;
                enumMemberValues.enabled = true;
              };
              updateImportsOnFileMove.enabled = "always";
              suggest.completeFunctionCalls = true;
            };
            javascript = {
              inlayHints = {
                parameterNames.enabled = "all";
                parameterTypes.enabled = true;
                variableTypes.enabled = true;
                propertyDeclarationTypes.enabled = true;
                functionLikeReturnTypes.enabled = true;
                enumMemberValues.enabled = true;
              };
              updateImportsOnFileMove.enabled = "always";
              suggest.completeFunctionCalls = true;
            };
            vtsls = {
              enableMoveToFileCodeAction = true;
              autoUseWorkspaceTsdk = true;
              experimental.completion.enableServerSideFuzzyMatch = true;
            };
          };
        };
        eslint = {
          enable = true;
          config = {
            root_markers = [
              ".eslintrc"
              ".eslintrc.js"
              ".eslintrc.cjs"
              ".eslintrc.mjs"
              ".eslintrc.json"
              ".eslintrc.yaml"
              ".eslintrc.yml"
              "eslint.config.js"
              "eslint.config.mjs"
              "eslint.config.cjs"
              "eslint.config.ts"
              "package.json"
            ];
            settings = {
              workingDirectories.mode = "auto";
              format = false;
            };
          };
        };
      };
      plugins.conform-nvim.settings.formatters_by_ft = {
        javascript = [ "prettier" ];
        javascriptreact = [ "prettier" ];
        typescript = [ "prettier" ];
        typescriptreact = [ "prettier" ];
      };
    };
  };
}
