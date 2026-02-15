# Git GUI-specific settings (1Password SSH signing on Linux)
{ lib, pkgs, ... }:
{
  programs.git.settings.gpg.ssh = lib.optionalAttrs pkgs.stdenv.isLinux {
    program = "${pkgs._1password-gui}/bin/op-ssh-sign";
  };
}
