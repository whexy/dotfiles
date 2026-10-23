{ pkgs }:
let
  inherit (pkgs) lib python3;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
    ];
  };

  dependencies = with python3.pkgs; [
    mcp
    starlette
    uvicorn
  ];

  # The interpreter basedpyright resolves imports against.
  devPython = python3.withPackages (_: dependencies);

  sourceCheck =
    name: nativeBuildInputs: script:
    pkgs.runCommand "spark-mcp-${name}" { inherit nativeBuildInputs; } ''
      cp -r ${src} source && chmod -R u+w source && cd source
      export HOME=$TMPDIR
      ${script}
      touch $out
    '';
in
python3.pkgs.buildPythonApplication {
  pname = "spark-mcp";
  version = "0.1.0";
  pyproject = true;
  inherit src dependencies;

  build-system = [ python3.pkgs.hatchling ];
  pythonImportsCheck = [ "spark_mcp.server" ];

  passthru.tests = {
    typecheck = sourceCheck "typecheck" [ pkgs.basedpyright ] ''
      basedpyright --pythonpath ${devPython}/bin/python3
    '';
    lint = sourceCheck "lint" [ pkgs.ruff ] ''
      ruff check --no-cache .
      ruff format --no-cache --check .
    '';
  };

  meta = {
    description = "Spark's email search and reading tools as a remote MCP server";
    mainProgram = "spark-mcp";
    # Spark Desktop, which the CLI talks to, has no Linux build.
    platforms = lib.platforms.darwin;
  };
}
