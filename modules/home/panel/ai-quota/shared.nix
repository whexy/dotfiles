# Shared API and provider metadata for the AI-quota bar renderers.
let
  # A path literal sits inside the flake source, and `toString` on it embeds
  # that whole tree's store path without depending on it, so every repo edit
  # would rebuild the bars. The logos get a store path of their own instead.
  logos = builtins.path {
    path = ./logos;
    name = "ai-quota-logos";
  };
in
{
  inherit logos;

  apiUrl = "https://ai-quota.clusters.work/api/quota";
  updateInterval = 30;

  providers = [
    {
      name = "claude";
      title = "Claude";
      variable = "claude";
      icon = "󰚩";
      logo = "${logos}/claude.png";
    }
    {
      name = "kimi";
      title = "Kimi";
      variable = "kimi";
      icon = "󰽥";
      logo = "${logos}/kimi.png";
    }
    {
      name = "codex";
      title = "Codex";
      variable = "codex";
      icon = "󰚩";
      logo = "${logos}/codex.png";
    }
    {
      name = "antigravity";
      title = "Gemini";
      variable = "antigravity";
      icon = "󰇂";
      logo = "${logos}/antigravity.png";
    }
    {
      name = "grok";
      title = "Grok";
      variable = "grok";
      icon = "󰬅";
      logo = "${logos}/grok.png";
    }
  ];
}
