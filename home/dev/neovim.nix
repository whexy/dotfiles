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
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  xdg.configFile."nvim" = {
    source = ./nvim;
    recursive = true;
  };
}
