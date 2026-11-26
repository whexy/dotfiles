# Provide openssh-wsl package with Windows ssh.exe wrappers
# This allows using 1Password's Windows SSH agent from WSL
#
# The wrappers name Windows OpenSSH by absolute path: shells started by a
# service (Rex sessions, T3 Code terminals) have no Windows directories on
# PATH. Assumes the default automount root, /mnt.
#
# Note: This creates a SEPARATE package (openssh-wsl), not replacing openssh,
# because the system still needs real openssh for sshd.
_final: prev:
let
  wrap =
    name: prev.writeShellScriptBin name ''exec /mnt/c/Windows/System32/OpenSSH/${name}.exe "$@"'';
in
{
  openssh-wsl = prev.symlinkJoin {
    name = "openssh-wsl";
    paths = map wrap [
      "ssh"
      "ssh-add"
      "ssh-keygen"
      "scp"
      "sftp"
      "ssh-keyscan"
    ];
  };
}
