# Editor group: Neovim and Neovide.
{ lib, ... }:
{
  options.dotfiles.editor = {
    neovim = {
      enable = lib.mkEnableOption "Neovim";
      dev = lib.mkEnableOption "the full-featured development Neovim setup";
    };
    neovide.enable = lib.mkEnableOption "Neovide (Neovim GUI)";
  };

  imports = [
    ./neovim.nix
    ./neovim-dev.nix
    ./neovide.nix
  ];
}
