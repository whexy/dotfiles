{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.dotfiles.agents.enable {
    dotfiles.agents.harnesses.claude = {
      package = pkgs.llm-agents.claude-code;
      # The Bash tool otherwise runs the login shell, zsh, where unquoted
      # expansions do not word-split and unmatched globs abort the command;
      # models write bash and keep tripping on both.
      prelude = ''
        export CLAUDE_CODE_SHELL=${lib.getExe pkgs.bashInteractive}
      '';
      rules = {
        file = ".claude/CLAUDE.md";
        extraText = builtins.readFile ./SPECIAL_INSTRUCTION.md;
      };
      skillsRoot = ".claude/skills";
      settings = {
        entries = import ./models.nix {
          inherit lib;
          inherit (config.dotfiles) llmGateways;
        };
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
        # Before the link step, so a settings.json Home Manager still links
        # from a generation older than agent-settings is turned into the
        # user's own file instead of being removed with that generation.
        syncBeforeLinks = true;
      };
    };
  };
}
