# Git GUI-specific settings (1Password SSH signing on Linux)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.vcs;
in
{
  config = lib.mkIf cfg.git.opSshSigning {
    programs.git.settings.gpg.ssh = lib.optionalAttrs pkgs.stdenv.isLinux {
      program = "${pkgs._1password-gui}/bin/op-ssh-sign";
    };
  };
}
