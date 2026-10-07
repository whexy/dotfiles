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
  package = pkgs.runCommand "opencode" { meta.mainProgram = "opencode"; } ''
    mkdir -p $out/bin
    ln -s ${lib.getExe' upstream "opencode2"} $out/bin/opencode
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
