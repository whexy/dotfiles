# Minimal Neovim configuration for base capability
{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  programs.neovim = lib.mkDefault {
    enable = true;
    package = inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  xdg.configFile."nvim" = lib.mkDefault {
    source = ./nvim;
    recursive = true;
  };
}
