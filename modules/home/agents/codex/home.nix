{
  pkgs,
  lib,
  proxy,
  withModelPicker,
  mcp,
  prelude,
}:
let
  # Codex expands no `${VAR}` in header values; it reads a bearer token from
  # the variable `bearer_token_env_var` names, the same translation its own
  # import of Claude's MCP config makes.
  toCodex =
    server:
    let
      token = builtins.match "Bearer [$][{]([A-Za-z_][A-Za-z0-9_]*)[}]" (
        server.headers.Authorization or ""
      );
    in
    if token == null then
      server
    else
      removeAttrs server [ "headers" ] // { bearer_token_env_var = lib.head token; };

  agent = withModelPicker {
    name = "codex";
    package = pkgs.llm-agents.codex;
    mcpServers = lib.mapAttrs (_: toCodex) mcp.servers;
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
