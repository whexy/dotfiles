# Config files (YAML/TOML/JSON): language servers and formatters.
{
  config,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "config" {
    grammars = [
      "css"
      "html"
      "json"
      "json5"
      "toml"
      "yaml"
    ];
    nixvim = {
      plugins = {
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
