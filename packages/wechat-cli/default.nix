{ pkgs, flake }:
let
  inherit (pkgs) lib python3;

  # The skill is copied in at install, so editing it neither rebuilds the
  # source nor reruns its checks.
  fileset = lib.fileset.unions [
    ./pyproject.toml
    ./src
  ];
  src = lib.fileset.toSource {
    root = ./.;
    inherit fileset;
  };

  checks = flake.lib.pythonChecks {
    inherit pkgs fileset;
    dir = ./.;
  };
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

  passthru.tests = { inherit (checks) lint typecheck; };

  meta = {
    description = "Message your own WeChat through the wechat-relay service";
    mainProgram = "wechat";
    platforms = lib.platforms.unix;
  };
}
