# REA checks Ghidra and its JDK against its own requirements only when an
# agent first asks for deep analysis, so a bump that moves them past the pins
# here would otherwise surface as Ghidra "unavailable" mid-investigation.
# This runs the doctor scoped to Ghidra, then decompiles a small program end
# to end, which also compiles REA's bridge with the pinned javac.
{ pkgs, rea-agents }:
let
  program = pkgs.writeText "add.c" ''
    int add(int a, int b) { return a + b; }
    int main(int argc, char **argv) { (void) argv; return add(argc, 2); }
  '';
in
pkgs.runCommand "rea-ghidra"
  {
    nativeBuildInputs = [
      rea-agents
      pkgs.stdenv.cc
      pkgs.jq
    ];
  }
  ''
    export HOME=$TMPDIR
    rea doctor --provider ghidra --format json > doctor.json || true
    if [ "$(jq .healthy doctor.json)" != true ]; then
      cat doctor.json >&2
      exit 1
    fi

    cc -O0 -o add ${program}
    rea decompile ./add add --provider ghidra --format json > add.json
    jq -r .normalized_result add.json | tee pseudocode.c
    grep -q 'add(' pseudocode.c
    touch $out
  ''
