{ pkgs }:
let
  inherit (pkgs) lib python3;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
      ./tests
    ];
  };

  # The interpreter basedpyright resolves imports against, tests included.
  devPython = python3.withPackages (p: [
    p.textual
    p.tomlkit
    p.pytest
  ]);

  sourceCheck =
    name: nativeBuildInputs: script:
    pkgs.runCommand "agent-settings-${name}" { inherit nativeBuildInputs; } ''
      cp -r ${src} source && chmod -R u+w source && cd source
      export HOME=$TMPDIR
      ${script}
      touch $out
    '';
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
  nativeCheckInputs = [ python3.pkgs.pytestCheckHook ];

  passthru = {
    inherit devPython;
    tests = {
      typecheck = sourceCheck "typecheck" [ pkgs.basedpyright ] ''
        basedpyright --pythonpath ${devPython}/bin/python3
      '';
      lint = sourceCheck "lint" [ pkgs.ruff ] ''
        ruff check --no-cache .
        ruff format --no-cache --check .
      '';
    };
  };

  meta = {
    description = "Writable Claude Code and Codex model selection with Nix-maintained defaults";
    mainProgram = "agent-settings";
    platforms = lib.platforms.unix;
  };
}
