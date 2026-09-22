{ pkgs, ... }:
let
  python = pkgs.python3.withPackages (p: [ p.tomlkit ]);
in
pkgs.runCommand "agent-settings-tests" { } ''
  ${python}/bin/python3 ${./test.py} ${../../modules/home/agents/agent-settings.py}
  touch $out
''
