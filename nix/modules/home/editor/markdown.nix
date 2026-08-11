# Markdown: language server (prettier, in the web bundle, formats Markdown).
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.markdown.enable {
    home.packages = with pkgs; [
      mdx-language-server
    ];
  };
}
