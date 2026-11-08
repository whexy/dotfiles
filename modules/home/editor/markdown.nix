# Markdown: language server (prettier, in the web bundle, formats Markdown).
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "markdown" {
    grammars = [
      "markdown"
      "markdown_inline"
    ];
    nixvim = {
      extraPackages = [ pkgs.mdx-language-server ];
      filetype.extension.mdx = "mdx";
      plugins.treesitter.languageRegister.markdown = "mdx";
      lsp.servers.mdx_analyzer = {
        enable = true;
        package = null;
      };
      plugins.conform-nvim.settings.formatters_by_ft.mdx = [ "prettier" ];
    };
  };
}
