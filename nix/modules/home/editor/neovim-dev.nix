# Neovim configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.editor;
in
{
  config = lib.mkIf (cfg.neovim.enable && cfg.neovim.dev) {
    # Override base neovim configuration with full-featured dev setup
    programs.neovim = {
      enable = true;
      package = pkgs.unstable.neovim-unwrapped;
      viAlias = true;
      vimAlias = true;
    };

    xdg.configFile."nvim" = {
      source = ./nvim-dev;
      recursive = true;
    };

    home.shellAliases = {
      e = "nvim";
      r = "nvim -RM";
    };

    # Include unstable tree-sitter since NeoVim requires it
    home.packages = [
      pkgs.unstable.tree-sitter
    ];
  };
}
