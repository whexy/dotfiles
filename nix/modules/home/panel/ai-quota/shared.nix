# Shared metadata for the AI-quota bar renderers.
{ perSystem, ... }:
{
  aiQuota = "${perSystem.self.ai-quota}/bin/ai-quota";

  providers = [
    {
      name = "kimi";
      variable = "kimi";
      icon = "󰽥";
      logo = ./logos/kimi.png;
    }
    {
      name = "codex";
      variable = "codex";
      icon = "󰚩";
      logo = ./logos/codex.png;
    }
    {
      name = "opencode-go";
      variable = "opencode_go";
      icon = "󰘦";
      logo = ./logos/opencode-go.png;
    }
  ];
}
