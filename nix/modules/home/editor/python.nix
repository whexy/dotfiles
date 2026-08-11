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
      basedpyright
      black
      python3 # whatever version the channel provides
      ruff
      uv
    ];
  };
}
