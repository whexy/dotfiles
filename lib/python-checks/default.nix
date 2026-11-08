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
  # Files outside `dir` the tests also cover. With any, basedpyright is
  # given `.` and the files, so it ignores `include`; the package's
  # pyproject.toml then limits it with `exclude`.
  extraFiles ? [ ],
}:
let
  inherit (pkgs) lib;
  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions (
      [
        fileset
        ./pyproject.toml
      ]
      ++ extraFiles
    );
  };
  relative = path: lib.path.removePrefix root path;
  extra = lib.concatMapStrings (file: " \"$top\"/${lib.escapeShellArg (relative file)}") extraFiles;
  check =
    test: nativeBuildInputs: script:
    pkgs.runCommand "${baseNameOf dir}-${test}" { inherit nativeBuildInputs; } ''
      cp -r ${src} source && chmod -R u+w source
      top=$PWD/source
      cd "$top"/${relative dir}
      export HOME=$TMPDIR
      ${script}
      touch $out
    '';
in
{
  # sourceTest NAME NATIVEBUILDINPUTS SCRIPT runs SCRIPT the same way.
  sourceTest = check;
  lint = check "lint" [ pkgs.ruff ] ''
    ruff check --no-cache .${extra}
    ruff format --no-cache --check .${extra}
  '';
  typecheck = check "typecheck" [ pkgs.basedpyright ] ''
    basedpyright --pythonpath ${python}/bin/python3${
      lib.optionalString (extraFiles != [ ]) " .${extra}"
    }
  '';
}
