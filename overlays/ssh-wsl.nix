# Provide openssh-wsl package with Windows ssh.exe wrappers
# This allows using 1Password's Windows SSH agent from WSL
# Windows OpenSSH is in C:\WINDOWS\System32\OpenSSH (always in PATH)
#
# Note: This creates a SEPARATE package (openssh-wsl), not replacing openssh,
# because the system still needs real openssh for sshd.
_final: prev: {
  openssh-wsl = prev.symlinkJoin {
    name = "openssh-wsl";
    paths = [
      (prev.writeShellScriptBin "ssh" ''exec ssh.exe "$@"'')
      (prev.writeShellScriptBin "ssh-add" ''exec ssh-add.exe "$@"'')
      (prev.writeShellScriptBin "ssh-keygen" ''exec ssh-keygen.exe "$@"'')
      (prev.writeShellScriptBin "scp" ''exec scp.exe "$@"'')
      (prev.writeShellScriptBin "sftp" ''exec sftp.exe "$@"'')
      (prev.writeShellScriptBin "ssh-keyscan" ''exec ssh-keyscan.exe "$@"'')
    ];
  };
}
