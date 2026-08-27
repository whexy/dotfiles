# Shared metadata for the AI-quota bar renderers.
{ perSystem, ... }:
{
  aiQuota = "${perSystem.self.ai-quota}/bin/ai-quota";

  providers = [
    {
      name = "kimi";
      variable = "kimi";
      icon = "󰽥";
    }
    {
      name = "codex";
      variable = "codex";
      icon = "󰚩";
    }
    {
      name = "opencode-go";
      variable = "opencode_go";
      icon = "󰘦";
    }
  ];
}
