{
  pkgs,
  lib,
  apiAccounts,
  proxyAccounts,
}:
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  # defaultProvider = if proxyAccounts then "ai-proxy" else "opencode-go";
  # defaultModel = if proxyAccounts then "gpt-5.6-sol" else "glm-5.3-flash";

  defaultProvider = "opencode-go";
  defaultModel = "glm-5.3-flash";

  packages = [
    "npm:pi-web-access"
    "npm:@narumitw/pi-goal"
    "npm:pi-subagents"
  ];

  npmCommand = [ "${pkgs.nodejs}/bin/npm" ];

  # Scoped models for Ctrl+P cycling (`/scoped-models`).
  enabledModels = [
    "opencode-go/glm-5.3-flash"
  ]
  ++ lib.optionals proxyAccounts [
    "ai-proxy/gpt-5.6-sol"
    "ai-proxy/kimi-k3-256k"
    "ai-proxy/kimi-k3"
    "ai-proxy/claude-opus-5"
    "ai-proxy/claude-fable-5"
  ]
  ++ [
    # OpenCode Go subscription
    "opencode-go/deepseek-v4-flash"
    "opencode-go/deepseek-v4-pro"
    "opencode-go/glm-5.3"
    "opencode-go/kimi-k3"
    "opencode-go/gpt-5.6-luna"
    # OpenRouter
    "openrouter/z-ai/glm-5.3-flash"
    "openrouter/z-ai/glm-5.3"
    "openrouter/moonshotai/kimi-k3"
  ]
  ++ lib.optionals apiAccounts [
    # Pay by APIs
    "openai/gpt-5.6-sol"
    "deepseek/deepseek-v4-flash"
    "deepseek/deepseek-v4-pro"
    "anthropic/claude-opus-5"
    "anthropic/claude-sonnet-5"
    "anthropic/claude-fable-5"
  ]
  ++ lib.optionals proxyAccounts [
    "ai-proxy/gpt-5.6-terra"
    "ai-proxy/gpt-5.6-luna"
    "ai-proxy/gemini-3.7-flash"
    "ai-proxy/gemini-3.1-pro-preview"
  ];
}
