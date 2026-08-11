# Typst: compiler, language server, and formatter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.typst.enable {
    home.packages = with pkgs; [
      tinymist
      typst
      typstyle
    ];
  };
}
