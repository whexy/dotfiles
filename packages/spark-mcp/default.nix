{ pkgs, flake }:
let
  inherit (pkgs) lib python3;

  fileset = lib.fileset.unions [
    ./pyproject.toml
    ./src
    ./tests
  ];
  src = lib.fileset.toSource {
    root = ./.;
    inherit fileset;
  };

  dependencies = with python3.pkgs; [
    mcp
    pyjwt
    cryptography
    starlette
    uvicorn
  ];

  # The interpreter basedpyright resolves imports against.
  devPython = python3.withPackages (_: dependencies);

  checks = flake.lib.pythonChecks {
    inherit pkgs fileset;
    dir = ./.;
    python = devPython;
  };
in
python3.pkgs.buildPythonApplication {
  pname = "spark-mcp";
  version = "0.1.0";
  pyproject = true;
  inherit src dependencies;

  build-system = [ python3.pkgs.hatchling ];
  pythonImportsCheck = [ "spark_mcp.server" ];
  nativeCheckInputs = [ python3.pkgs.pytestCheckHook ];

  passthru.tests = { inherit (checks) lint typecheck; };

  meta = {
    description = "Spark's email search and reading tools as a remote MCP server";
    mainProgram = "spark-mcp";
    # Spark Desktop, which the CLI talks to, has no Linux build.
    platforms = lib.platforms.darwin;
  };
}
