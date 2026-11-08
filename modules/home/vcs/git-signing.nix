# Use forwarded agents over SSH and the 1Password integration on local desktops.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.vcs;
  onepassword =
    if osConfig != null then osConfig.programs._1password-gui.package else pkgs._1password-gui;
  localSigner =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else
      "${onepassword}/bin/op-ssh-sign";
  signer = pkgs.writeShellScript "ssh-sign" ''
    if [ -n "''${SSH_CONNECTION:-}" ]; then
      exec ${pkgs.openssh}/bin/ssh-keygen "$@"
    fi
    exec ${lib.escapeShellArg localSigner} "$@"
  '';
in
{
  config =
    lib.mkIf
      (
        cfg.git.enable
        && cfg.git.signing.enable
        && (pkgs.stdenv.hostPlatform.isDarwin || cfg.git.opSshSigning)
      )
      {
        programs.git.settings.gpg.ssh.program = toString signer;
      };
}
