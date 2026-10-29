{ pkgs, ... }:
pkgs.runCommand "bot-update-rollout"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (p: [ p.pyyaml ]))
      pkgs.git
      pkgs.bash
    ];
  }
  ''
    python ${./test.py} ${../../.woodpecker.yml}
    touch "$out"
  ''
