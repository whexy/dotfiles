# Neovim configuration
{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  # Override base neovim configuration with full-featured dev setup
  programs.neovim = {
    enable = lib.mkForce true;
    package = lib.mkForce inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
    defaultEditor = lib.mkForce true;
    viAlias = lib.mkForce true;
    vimAlias = lib.mkForce true;
  };

  xdg.configFile."nvim" = lib.mkForce {
    source = ./nvim;
    recursive = true;
  };
}
