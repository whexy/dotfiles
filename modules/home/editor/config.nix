# Config files (YAML/TOML/JSON): language servers and formatters.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.config.enable {
    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins = {
        treesitter.grammarPackages = with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
          css
          html
          json
          json5
          toml
          yaml
        ];
        conform-nvim.settings.formatters_by_ft = {
          html = [ "prettier" ];
          json = [ "prettier" ];
          toml = [ "tombi" ];
          yaml = [ "yamlfmt" ];
        };
        lint.lintersByFt.toml = [ "tombi" ];
      };
      lsp.servers = {
        cssls = {
          enable = true;
          config.settings = {
            css = {
              validate = true;
              lint.unknownAtRules = "ignore";
            };
            scss.validate = true;
            less.validate = true;
          };
        };
        html = {
          enable = true;
        };
        jsonls = {
          enable = true;
          config.settings.json = {
            format.enable = true;
            validate.enable = true;
          };
        };
        tombi = {
          enable = true;
        };
        yamlls = {
          enable = true;
        };
      };
    };
  };
}
