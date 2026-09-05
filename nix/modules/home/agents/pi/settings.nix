{
  pkgs,
  lib,
  apiAccounts,
  proxyAccounts,
  defaults,
}:
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  inherit (defaults) defaultProvider defaultModel;

  packages = [
    "npm:pi-web-access"
    "npm:@narumitw/pi-goal"
    "npm:pi-subagents"
    "npm:pi-background-tasks"
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
        "openrouter/meta/muse-spark-1.3-contributor"
        # (61) GPT-5.6 Sol, GPT-6-astra
        "ai-proxy/gpt-5.6-sol"
        "ai-proxy/gpt-6-astra"
        # (61) Grok 4.6
        "ai-proxy/grok-4.6"
        # (60) Kimi K3, GLM 5.3
        "ai-proxy/kimi-k3-256k"
        "ai-proxy/kimi-k3"
        "openrouter/moonshotai/kimi-k3"
        "openrouter/z-ai/glm-5.3"
        # (59) Gemini 3.8 Flash
        "ai-proxy/gemini-3.8-flash"
        # (58) Claude Sonnet 5
        "ai-proxy/claude-sonnet-5"

        # Two cheap models for simpler task
        # (57) GLM-5.3-Flash
        "openrouter/z-ai/glm-5.3-flash"
        # (52) GPT-5.6 Luna
        "ai-proxy/gpt-5.6-luna"

        # API billing (payed by lab)
        "openai/gpt-6-astra"
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
