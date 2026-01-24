# Neovim configuration
{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  programs.vim = {
    enable = lib.mkForce false;
    defaultEditor = lib.mkForce false;
  };

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
