{
  pkgs,
  lib,
  proxy,
  withModelPicker,
  mcp,
  prelude,
}:
let
  agent = withModelPicker {
    name = "codex";
    package = pkgs.llm-agents.codex;
    mcpServers = mcp.servers;
    inherit prelude;
    managedLinks = [ "AGENTS.md" ];
    resetEnv = [
      "OPENAI_BASE_URL"
      "CODEX_API_KEY"
    ];
    entries = import ./models.nix {
      codexVersion = pkgs.llm-agents.codex.version;
      inherit
        proxy
        ;
    };
  };
in
{
  packages = [ agent ];
  activation.codexSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${agent}/bin/codex-settings-sync
  '';
}
