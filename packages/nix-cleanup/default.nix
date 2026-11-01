{
  pkgs,
  nixPackage ? pkgs.nix,
  ...
}:
pkgs.writeShellApplication {
  name = "nix-cleanup";
  runtimeInputs = [
    pkgs.python3
    nixPackage
  ];
  text = ''
    exec python3 -I ${./cleanup.py} "$@"
  '';
  derivationArgs.postCheck = ''
    ${pkgs.python3}/bin/python3 ${./.}/test_cleanup.py
  '';
}
