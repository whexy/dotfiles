# Shared metadata for the AI-quota bar renderers.
{ perSystem, ... }:
{
  aiQuota = "${perSystem.self.ai-quota}/bin/ai-quota";

  providers = [
    {
      name = "kimi";
      title = "Kimi";
      variable = "kimi";
      icon = "󰽥";
      logo = ./logos/kimi.png;
    }
    {
      name = "codex";
      title = "Codex";
      variable = "codex";
      icon = "󰚩";
      logo = ./logos/codex.png;
    }
    {
      name = "opencode-go";
      title = "OpenCode Go";
      variable = "opencode_go";
      icon = "󰘦";
      logo = ./logos/opencode-go.png;
    }
  ];
}
