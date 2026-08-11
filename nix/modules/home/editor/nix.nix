# Nix: language server and formatter.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.editor.nix.enable {
    home.packages = with pkgs; [
      nixd
      nixfmt
    ];
  };
}
