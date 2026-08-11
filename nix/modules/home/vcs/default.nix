# VCS group: git and git-adjacent tools.
{ lib, ... }:
{
  options.dotfiles.vcs = {
    git = {
      enable = lib.mkEnableOption "git";
      opSshSigning = lib.mkEnableOption "1Password SSH signing (op-ssh-sign) on Linux";
    };
  };

  imports = [
    ./git.nix
    ./git-signing.nix
  ];
}
