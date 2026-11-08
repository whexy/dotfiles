# API and provider metadata shared by the popup and the AI-quota bar pills.
let
  # A path literal sits inside the flake source, and `toString` on it embeds
  # that whole tree's store path without depending on it, so every repo edit
  # would rebuild the bars. The logos get a store path of their own instead.
  logos = builtins.path {
    path = ./logos;
    name = "ai-quota-logos";
  };

  # Brand accents, in the order renderers emit their rules. summary.jq tags
  # each quota window with its provider's accent name.
  accents = [
    {
      name = "gray";
      hex = "#98989d";
    }
    {
      name = "blue";
      hex = "#007cff";
    }
    {
      name = "green";
      hex = "#10a37f";
    }
    {
      name = "orange";
      hex = "#d97757";
    }
    {
      name = "cyan";
      hex = "#22b8cf";
    }
    {
      name = "white";
      hex = "#ffffff";
    }
  ];
  accent = name: builtins.head (builtins.filter (a: a.name == name) accents);
in
{
  inherit accents logos;

  apiUrl = "https://ai-quota.clusters.work/api/quota";
  updateInterval = 30;

  # logoScale fits each logo into SketchyBar's icon slot; tmuxColor is the
  # catppuccin palette slot tmux draws the provider's name in.
  providers = [
    {
      name = "claude";
      title = "Claude";
      variable = "claude";
      icon = "󰚩";
      logo = "${logos}/claude.png";
      logoScale = 0.026;
      accent = accent "orange";
      tmuxColor = "peach";
    }
    {
      name = "kimi";
      title = "Kimi";
      variable = "kimi";
      icon = "󰽥";
      logo = "${logos}/kimi.png";
      logoScale = 0.025;
      accent = accent "blue";
      tmuxColor = "blue";
    }
    {
      name = "codex";
      title = "Codex";
      variable = "codex";
      icon = "󰚩";
      logo = "${logos}/codex.png";
      logoScale = 0.027;
      accent = accent "green";
      tmuxColor = "green";
    }
    {
      name = "antigravity";
      title = "Gemini";
      variable = "antigravity";
      icon = "󰇂";
      logo = "${logos}/antigravity.png";
      logoScale = 0.026;
      accent = accent "gray";
      tmuxColor = "mauve";
    }
    {
      name = "grok";
      title = "Grok";
      variable = "grok";
      icon = "󰬅";
      logo = "${logos}/grok.png";
      logoScale = 0.026;
      accent = accent "white";
      tmuxColor = "fg";
    }
    {
      name = "meta";
      title = "Muse";
      variable = "meta";
      icon = "󰛤";
      logo = "${logos}/meta.png";
      logoScale = 0.026;
      accent = accent "blue";
      tmuxColor = "blue";
    }
    {
      name = "opencode-go";
      title = "OpenCode";
      variable = "opencode_go";
      icon = "󰅴";
      logo = "${logos}/opencode-go.png";
      logoScale = 0.025;
      accent = accent "gray";
      tmuxColor = "fg";
    }
    {
      name = "zed";
      title = "Zed";
      variable = "zed";
      icon = "󰬡";
      logo = "${logos}/zed.png";
      logoScale = 0.024;
      accent = accent "cyan";
      tmuxColor = "sky";
    }
  ];
}
