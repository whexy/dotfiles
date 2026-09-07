# Use forwarded agents over SSH and the 1Password integration on local desktops.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.vcs;
  localSigner =
    if pkgs.stdenv.isDarwin then
      "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else
      "${pkgs._1password-gui}/bin/op-ssh-sign";
  signer = pkgs.writeShellScript "ssh-sign" ''
    if [ -n "''${SSH_CONNECTION:-}" ]; then
      exec ${pkgs.openssh}/bin/ssh-keygen "$@"
    fi
    exec ${lib.escapeShellArg localSigner} "$@"
  '';
in
{
  config = lib.mkIf (cfg.git.enable && (pkgs.stdenv.isDarwin || cfg.git.opSshSigning)) {
    programs.git.settings.gpg.ssh.program = toString signer;
  };
}
