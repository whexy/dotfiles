{
  pkgs,
  lib,
  apiAccounts,
  proxyAccounts,
}:
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  defaultProvider = if proxyAccounts then "ai-proxy" else "opencode-go";
  defaultModel = if proxyAccounts then "claude-opus-5" else "muse-spark-1.3-contributor";

  packages = [
    "npm:pi-web-access"
    "npm:@narumitw/pi-goal"
    "npm:pi-subagents"
  ];

  npmCommand = [ "${pkgs.nodejs}/bin/npm" ];

  # Scoped models for Ctrl+P cycling (`/scoped-models`).
  enabledModels =
    let
      models = [
        # (66) Claude Fable 5.1
        "ai-proxy/claude-fable-5-1"
        # (63) Claude Opus 5
        "ai-proxy/claude-opus-5"
        # (62) Muse Spark 1.3
        "opencode-go/muse-spark-1.3-contributor"
        # (61) GPT-5.6 Sol
        "ai-proxy/gpt-5.6-sol"
        # (61) Grok 4.6
        "opencode-go/grok-4.6"
        # (60) Kimi K3
        "ai-proxy/kimi-k3-256k"
        "ai-proxy/kimi-k3"
        "opencode-go/kimi-k3"
        "openrouter/moonshotai/kimi-k3"
        # (60) GLM 5.3
        "opencode-go/glm-5.3"
        "openrouter/z-ai/glm-5.3"
        # (59) Gemini 3.8 Flash
        "ai-proxy/gemini-3.8-flash"

        # Two cheap models for simpler task
        # (57) GLM-5.3-Flash
        "opencode-go/glm-5.3-flash"
        "openrouter/z-ai/glm-5.3-flash"
        # (52) GPT-5.6 Luna
        "ai-proxy/gpt-5.6-luna"
        "opencode-go/gpt-5.6-luna"

        # API billing (payed by lab)
        "openai/gpt-5.6-sol"
        "openai/gpt-5.6-terra"
        "openai/gpt-5.6-luna"
        "anthropic/claude-fable-5-1"
        "anthropic/claude-opus-5"
        "anthropic/claude-sonnet-5"
      ];
      modelEnabled =
        model:
        if lib.hasPrefix "ai-proxy/" model then
          proxyAccounts
        else if lib.hasPrefix "openai/" model || lib.hasPrefix "anthropic/" model then
          apiAccounts
        else
          true;
    in
    lib.filter modelEnabled models;
}
