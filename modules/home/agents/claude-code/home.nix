{
  pkgs,
  lib,
  proxy,
  withModelPicker,
  mcp,
}:
let
  agent = withModelPicker {
    name = "claude";
    package = pkgs.llm-agents.claude-code;
    mcpServers = mcp.servers;
    prelude = mcp.exportSecrets;
    managedLinks = [
      "CLAUDE.md"
      "skills"
    ];
    # Also maintain these rules for standalone Home Manager installations;
    # system-managed hosts additionally enforce them through managed policy.
    maintainedSettings = builtins.fromJSON (builtins.readFile ./settings.json);
    resetEnv = [
      "ANTHROPIC_AUTH_TOKEN"
      "CLAUDE_CODE_OAUTH_TOKEN"
      "CLAUDE_CODE_USE_BEDROCK"
      "CLAUDE_CODE_USE_VERTEX"
      "CLAUDE_CODE_USE_FOUNDRY"
    ];
    entries = import ./models.nix {
      inherit
        proxy
        ;
    };
  };
in
{
  packages = [ agent ];
  # Shared global rules plus Claude Code-only guidance.
  homeFiles.".claude/CLAUDE.md".text =
    builtins.readFile ../AGENTS.md + "\n" + builtins.readFile ./SPECIAL_INSTRUCTION.md;
  activation.claudeSettings = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
    run ${agent}/bin/claude-settings-sync
  '';
}
