{ pkgs, ... }:
let
  python = pkgs.python3.withPackages (p: [ p.msgpack ]);
  ssh = pkgs.writeShellScriptBin "ssh" ''
    exec ${python}/bin/python ${../packages/neovide-remote/fake-ssh.py} "$@"
  '';
  package = import ../packages/neovide-remote/default.nix {
    pkgs = pkgs // {
      openssh = ssh;
    };
  };
in
pkgs.runCommand "neovide-remote-test"
  {
    nativeBuildInputs = [
      python
      pkgs.neovim
      pkgs.socat
    ]
    ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.mono;
  }
  ''
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    python ${../packages/neovide-remote/test.py} ${package}/bin/neovide-remote
    ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      mcs -target:exe -main:TestRelay -r:System.Windows.Forms -r:System.Xml \
        -out:relay-test.exe ${../packages/neovide-remote/windows/Relay.cs} ${../packages/neovide-remote/windows/TestRelay.cs}
      mono relay-test.exe
    ''}
    touch $out
  ''
