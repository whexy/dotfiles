# Python: toolchain, package manager, language servers, and formatter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.python.enable {
    home.packages = with pkgs; [
      python3 # whatever version the channel provides
      uv
    ];

    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [ python ];
      lsp.servers = {
        basedpyright = {
          enable = true;
        };
        ruff = {
          enable = true;
        };
      };
      plugins.conform-nvim.settings.formatters_by_ft.python = [
        "ruff_fix"
        "ruff_organize_imports"
        "ruff_format"
      ];
    };
  };
}
