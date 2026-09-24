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
  devPython = python3.withPackages (p: [ p.pytest ]);

  sourceCheck =
    name: nativeBuildInputs: script:
    pkgs.runCommand "wechat-cli-${name}" { inherit nativeBuildInputs; } ''
      cp -r ${src} source && chmod -R u+w source && cd source
      export HOME=$TMPDIR
      ${script}
      touch $out
    '';
in
python3.pkgs.buildPythonApplication {
  pname = "wechat-cli";
  version = "0.2.0";
  pyproject = true;
  inherit src;

  build-system = [ python3.pkgs.hatchling ];
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
    description = "Message your own WeChat through the wechat-relay service";
    mainProgram = "wechat";
    platforms = lib.platforms.unix;
  };
}
