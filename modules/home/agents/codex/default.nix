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
    name = "codex";
    package = pkgs.llm-agents.codex;
    mcpServers = cfg.mcp.rendered.codex;
    inherit (cfg.launcher) prelude;
    managedLinks = [ "AGENTS.md" ];
    resetEnv = [
      "OPENAI_BASE_URL"
      "CODEX_API_KEY"
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
      file.".codex/AGENTS.md".source = ../global-rules.md;
      activation.codexSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${agent}/bin/codex-settings-sync
      '';
    };
  };
}
