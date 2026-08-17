{
  pkgs,
  lib,
  apiAccounts,
  proxyAccounts,
}:
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  # kimi-k3 goes through the tailnet AI proxy; fall back to OpenCode Go without Tailscale.
  defaultProvider = if proxyAccounts then "ai-proxy" else "opencode-go";
  defaultModel = if proxyAccounts then "kimi-k3" else "deepseek-v4-pro";

  packages = [
    "npm:pi-web-access"
  ];

  npmCommand = [ "${pkgs.nodejs}/bin/npm" ];

  # Scoped models for Ctrl+P cycling (`/scoped-models`).
  enabledModels =
    lib.optionals proxyAccounts [
      "ai-proxy/kimi-k3"
      "ai-proxy/kimi-k3-256k"
      "ai-proxy/gpt-5.6-sol"
    ]
    ++ [
      # OpenCode Go subscription (always available)
      "opencode-go/deepseek-v4-pro"
      "opencode-go/deepseek-v4-flash"
      "opencode-go/grok-4.5"
      "opencode-go/gpt-5.6-luna"
      "opencode-go/qwen3.8-max"
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
      "ai-proxy/gemini-3.6-flash"
      "ai-proxy/gemini-3.1-pro-preview"
    ];
}
