# VCS group: git and git-adjacent tools.
{ inputs, lib, ... }:
{
  options.dotfiles.vcs = {
    git = {
      enable = lib.mkEnableOption "git";
      opSshSigning = lib.mkEnableOption "1Password SSH signing (op-ssh-sign) on Linux";
    };
    hunk.enable = lib.mkEnableOption "hunk (terminal diff tool and git pager)";
  };

  imports = [
    inputs.hunk.homeManagerModules.default
    ./git.nix
    ./git-signing.nix
    ./hunk.nix
  ];
}
