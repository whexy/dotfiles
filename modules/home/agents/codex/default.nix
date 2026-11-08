{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.dotfiles.agents.enable {
    dotfiles.agents.harnesses.codex = {
      package = pkgs.llm-agents.codex;
      rules.file = ".codex/AGENTS.md";
      skillsRoot = ".agents/skills";
      settings = {
        entries = import ./models.nix {
          inherit lib;
          inherit (config.dotfiles) llmGateways;
        };
        managedLinks = [ "AGENTS.md" ];
        resetEnv = [
          "OPENAI_BASE_URL"
          "CODEX_API_KEY"
        ];
      };
    };
  };
}
