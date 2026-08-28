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
    "npm:@agentoom/pi-spending-guard"
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
  ]
  ++ [
    # OpenCode Go subscription
    "opencode-go/deepseek-v4-pro"
    "opencode-go/deepseek-v4-flash"
    "opencode-go/grok-4.6"
    "opencode-go/gpt-5.6-luna"
  ]
  ++ lib.optionals apiAccounts [
    # Pay by APIs
    "openai/gpt-5.6-sol"
    "deepseek/deepseek-v4-flash"
    "deepseek/deepseek-v4-pro"
    "openrouter/z-ai/glm-5.3-flash"
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
