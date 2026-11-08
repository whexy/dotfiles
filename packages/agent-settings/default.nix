{ pkgs, flake }:
let
  inherit (pkgs) lib python3;

  fileset = lib.fileset.unions [
    ./pyproject.toml
    ./src
  ];
  src = lib.fileset.toSource {
    root = ./.;
    inherit fileset;
  };

  # The interpreter basedpyright resolves imports against.
  devPython = python3.withPackages (p: [
    p.textual
    p.tomlkit
  ]);

  checks = flake.lib.pythonChecks {
    inherit pkgs fileset;
    dir = ./.;
    python = devPython;
  };
in
python3.pkgs.buildPythonApplication {
  pname = "agent-settings";
  version = "1.0.0";
  pyproject = true;
  inherit src;

  build-system = [ python3.pkgs.hatchling ];
  dependencies = [
    python3.pkgs.tomlkit
    python3.pkgs.textual
  ];

  passthru = {
    inherit devPython;
    tests = { inherit (checks) lint typecheck; };
  };

  meta = {
    description = "Writable Claude Code, Codex, and Muse Code model selection with Nix-maintained defaults";
    mainProgram = "agent-settings";
    platforms = lib.platforms.unix;
  };
}
