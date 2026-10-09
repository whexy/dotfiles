{
  pkgs,
  lib,
  proxy,
  defaults,
  mcp,
}:
let
  upstream = pkgs.llm-agents.opencode2;
  # The package installs its binary as `opencode2` to coexist with v1.
  #
  # The shared background server inherits the environment of the launch that
  # starts it and resolves `{env:...}` from there, so it keeps the MCP secrets
  # it started with until `opencode service restart`.
  package = pkgs.writeShellScriptBin "opencode" ''
    ${mcp.exportSecrets}
    exec ${lib.getExe' upstream "opencode2"} "$@"
  '';
  settings = import ./config.nix {
    inherit
      pkgs
      lib
      proxy
      defaults
      mcp
      ;
  };
in
{
  packages = [ package ];
  shellAliases.oc = "opencode";
  homeFiles.".config/opencode/opencode.json".text = builtins.toJSON settings;
}
