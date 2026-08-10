# Neovim configuration
{
  pkgs,
  ...
}:
{
  # Override base neovim configuration with full-featured dev setup
  programs.neovim = {
    enable = true;
    package = pkgs.unstable.neovim-unwrapped;
    viAlias = true;
    vimAlias = true;
  };

  xdg.configFile."nvim" = {
    source = ./nvim;
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
}
