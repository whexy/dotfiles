# Shell scripts: linter and formatter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.shell.enable {
    home.packages = with pkgs; [
      shellcheck
      shfmt
    ];
  };
}
