{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents;
  withModelPicker = import ../launcher/with-model-picker.nix {
    inherit pkgs;
    agentSettings = perSystem.self.agent-settings;
  };
  agent = withModelPicker {
    name = "claude";
    package = pkgs.llm-agents.claude-code;
    mcpServers = cfg.mcp.servers;
    # The Bash tool otherwise runs the login shell, zsh, where unquoted
    # expansions do not word-split and unmatched globs abort the command;
    # models write bash and keep tripping on both.
    prelude = cfg.launcher.prelude + ''
      export CLAUDE_CODE_SHELL=${lib.getExe pkgs.bashInteractive}
    '';
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
      inherit lib;
      llmGateways = config.dotfiles.llmGateways;
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    home = {
      packages = [ agent ];
      # Shared global rules plus Claude Code-only guidance.
      file.".claude/CLAUDE.md".text =
        builtins.readFile ../global-rules.md + "\n" + builtins.readFile ./SPECIAL_INSTRUCTION.md;
      activation.claudeSettings = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        run ${agent}/bin/claude-settings-sync
      '';
    };
  };
}
