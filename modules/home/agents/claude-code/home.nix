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
  # Claude reads MCP servers from ~/.claude.json, a file it rewrites at
  # runtime (project history, auth state, onboarding flags), so Home Manager
  # cannot own it. --mcp-config points at a file we do own; the wrapper adds
  # it to every launch. `=` form, not a separate argument, so the flag cannot
  # swallow a following `mcp`/`doctor` subcommand as an extra config path.
  mcpConfig = pkgs.writeText "claude-mcp.json" (builtins.toJSON { mcpServers = mcp.servers; });
  mcpArgs = lib.optional (mcp.servers != { }) "--mcp-config=${mcpConfig}";
in
{
  packages = [
    (withModelPicker {
      name = "claude";
      package = pkgs.llm-agents.claude-code;
      extraArgs = mcpArgs;
      entries = import ./models.nix {
        inherit
          config
          lib
          apiAccounts
          proxyAccounts
          proxy
          ;
      };
    })
  ];
  homeFiles.".claude/settings.json".source = ./settings.json;
}
