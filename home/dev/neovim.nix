# Neovim configuration
{
  pkgs,
  inputs,
  ...
}:
{
  # Override base neovim configuration with full-featured dev setup
  programs.neovim = {
    enable = true;
    package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  xdg.configFile."nvim" = {
    source = ./nvim;
    recursive = true;
  };
}
