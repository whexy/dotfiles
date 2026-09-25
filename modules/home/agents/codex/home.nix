{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
  proxy,
  withModelPicker,
  mcp,
}:
let
  agent = withModelPicker {
    name = "codex";
    package = pkgs.llm-agents.codex;
    mcpServers = mcp.servers;
    managedLinks = [ "AGENTS.md" ];
    resetEnv = [
      "OPENAI_BASE_URL"
      "CODEX_API_KEY"
    ];
    entries = import ./models.nix {
      inherit
        config
        lib
        apiAccounts
        proxyAccounts
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
