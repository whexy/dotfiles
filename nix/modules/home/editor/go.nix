# Go: toolchain, language server, and linter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.go.enable {
    home.packages = with pkgs; [
      go
      golangci-lint
      gopls
    ];
  };
}
