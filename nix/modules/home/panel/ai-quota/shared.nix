# Shared API and provider metadata for the AI-quota bar renderers.
{
  apiUrl = "https://ai-quota.clusters.work/api/quota";
  updateInterval = 30;

  providers = [
    {
      name = "claude";
      title = "Claude";
      variable = "claude";
      icon = "󰚩";
      logo = ./logos/claude.png;
    }
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
      name = "antigravity";
      title = "Antigravity";
      variable = "antigravity";
      icon = "󰇂";
      logo = ./logos/antigravity.png;
    }
    {
      name = "grok";
      title = "Grok";
      variable = "grok";
      icon = "󰬅";
      logo = ./logos/grok.png;
    }
  ];
}
