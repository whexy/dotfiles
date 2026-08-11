# Shell group: zsh.
{ lib, ... }:
{
  options.dotfiles.shell = {
    zsh = {
      enable = lib.mkEnableOption "zsh";
      devExtras = lib.mkEnableOption "shell developer extras (p10k prompt, fzf, zoxide, bat, direnv)";
    };
  };

  imports = [
    ./zsh.nix
    ./zsh-extras.nix
  ];
}
