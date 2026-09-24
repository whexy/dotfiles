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
    p.cryptography
    p.qrcode
    p.pytest
  ]);

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
  version = "0.1.0";
  pyproject = true;
  inherit src;

  build-system = [ python3.pkgs.hatchling ];
  dependencies = [
    python3.pkgs.cryptography
    python3.pkgs.qrcode
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
    description = "Message your own WeChat through Tencent's iLink bot API";
    mainProgram = "wechat";
    platforms = lib.platforms.unix;
  };
}
