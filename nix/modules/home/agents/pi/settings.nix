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
  defaultProvider = if proxyAccounts then "moonshotai" else "opencode-go";
  defaultModel = if proxyAccounts then "kimi-k3" else "deepseek-v4-flash";

  packages = [
    "npm:pi-web-access"
  ];

  npmCommand = [ "${pkgs.nodejs}/bin/npm" ];

  # Scoped models for Ctrl+P cycling (`/scoped-models`).
  # kimi-k3 is only reachable via the tailnet AI proxy.
  enabledModels =
    lib.optionals proxyAccounts [
      "moonshotai/kimi-k3"
    ]
    ++ [
      # OpenCode Go subscription (always available)
      "opencode-go/deepseek-v4-flash"
      "opencode-go/grok-4.5"
      "opencode-go/gpt-5.6-luna"
      "opencode-go/qwen3.8-max"
    ]
    ++ lib.optionals apiAccounts [
      # Pay by APIs
      "openai/gpt-5.6-sol"
      "deepseek/deepseek-v4-flash"
      "anthropic/claude-opus-5"
      "anthropic/claude-sonnet-5"
      "anthropic/claude-fable-5"
    ]
    ++ lib.optionals proxyAccounts [
      "google/gemini-3.6-flash"
      "google/gemini-3.1-pro-preview"
    ];
}
