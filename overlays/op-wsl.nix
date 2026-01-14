# Override 1password-cli to use Windows op.exe in WSL
# op.exe is expected to be in PATH (via Windows PATH inherited by WSL)
final: prev: {
  _1password-cli = prev.writeShellScriptBin "op" ''
    exec op.exe "$@"
  '';
}
