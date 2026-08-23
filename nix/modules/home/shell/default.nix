# Shell group: zsh, motd.
{ lib, ... }:
{
  options.dotfiles.shell = {
    motd = {
      enable = lib.mkEnableOption "system status message of the day (motd)";
    };
    zsh = {
      enable = lib.mkEnableOption "zsh";
      devExtras = lib.mkEnableOption "shell developer extras (p10k prompt, fzf, zoxide, bat, direnv)";
    };
  };

  imports = [
    ./motd.nix
    ./zsh.nix
    ./zsh-extras.nix
  ];
}
