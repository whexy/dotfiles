# Minimal Neovim configuration for base capability
{
  lib,
  pkgs,
  ...
}:
{
  programs.neovim = lib.mkDefault {
    enable = true;
    package = pkgs.unstable.neovim-unwrapped;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  xdg.configFile."nvim" = lib.mkDefault {
    source = ./nvim;
    recursive = true;
  };
}
