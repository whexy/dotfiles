{ config, lib }:
let
  inherit (config.dotfiles) tailscale;
in
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  # kimi-k3 goes through the tailnet AI proxy; fall back to OpenAI without Tailscale.
  defaultProvider = if tailscale then "moonshotai" else "openai";
  defaultModel = if tailscale then "kimi-k3" else "gpt-5.6-sol";

  # Scoped models for Ctrl+P cycling (`/scoped-models`).
  # kimi-k3 is only reachable via the tailnet AI proxy.
  enabledModels = lib.optional tailscale "moonshotai/kimi-k3" ++ [
    "openai/gpt-5.6-sol"
    "deepseek/deepseek-v4-flash"
    "anthropic/claude-opus-5"
    "anthropic/claude-fable-5"
    # OpenCode Go subscription
    "opencode-go/deepseek-v4-flash"
    "opencode-go/grok-4.5"
    "opencode-go/gpt-5.6-luna"
    "opencode-go/qwen3.8-max"
  ];
}
