# Markdown: language server (prettier, in the web bundle, formats Markdown).
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.markdown.enable {
    programs.nixvim = lib.mkIf config.dotfiles.editor.neovim.dev {
      extraPackages = [ pkgs.mdx-language-server ];
      filetype.extension.mdx = "mdx";
      plugins.treesitter.grammarPackages =
        with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
          markdown
          markdown_inline
        ];
      lsp.servers.mdx_analyzer = {
        enable = true;
        package = null;
      };
      plugins.conform-nvim.settings.formatters_by_ft.mdx = [ "prettier" ];
    };
  };
}
