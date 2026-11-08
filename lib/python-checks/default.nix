# The lint and typecheck tests of a Python package, for its passthru.tests.
# Its pyproject.toml extends ./pyproject.toml by relative path, so each test
# runs in a copy of the repository holding only `fileset` and that file.
let
  root = ../..;
in
{
  pkgs,
  # The package directory, where the tests run.
  dir,
  # The package's files the tests read, under `dir`.
  fileset,
  # The interpreter basedpyright resolves imports against.
  python ? pkgs.python3,
}:
let
  inherit (pkgs) lib;
  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      fileset
      ./pyproject.toml
    ];
  };
  check =
    test: nativeBuildInputs: script:
    pkgs.runCommand "${baseNameOf dir}-${test}" { inherit nativeBuildInputs; } ''
      cp -r ${src} source && chmod -R u+w source
      cd source/${lib.path.removePrefix root dir}
      export HOME=$TMPDIR
      ${script}
      touch $out
    '';
in
{
  # sourceTest NAME NATIVEBUILDINPUTS SCRIPT runs SCRIPT the same way.
  sourceTest = check;
  lint = check "lint" [ pkgs.ruff ] ''
    ruff check --no-cache .
    ruff format --no-cache --check .
  '';
  typecheck = check "typecheck" [ pkgs.basedpyright ] ''
    basedpyright --pythonpath ${python}/bin/python3
  '';
}
