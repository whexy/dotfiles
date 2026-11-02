{ pkgs }:
let
  inherit (pkgs) lib python3;

  # The skill is copied in at install, so editing it neither rebuilds the
  # source nor reruns its checks.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
    ];
  };

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

  postInstall = ''
    mkdir -p $out/share
    cp -r ${./skills} $out/share/skills
  '';

  passthru = {
    tests = {
      typecheck = sourceCheck "typecheck" [ pkgs.basedpyright ] ''
        basedpyright --pythonpath ${python3}/bin/python3
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
