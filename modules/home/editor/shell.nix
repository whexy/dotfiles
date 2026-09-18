# Shell scripts: linter and formatter.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.shell.enable {
    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      plugins = {
        treesitter.grammarPackages = with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
          bash
        ];
        conform-nvim.settings.formatters_by_ft.sh = [ "shfmt" ];
        lint.lintersByFt.sh = [ "shellcheck" ];
      };
    };
  };
}
