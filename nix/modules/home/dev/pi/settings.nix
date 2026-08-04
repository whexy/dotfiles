{ config }:
let
  inherit (config.dotfiles) tailscale;
in
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  # kimi-k3 goes through the tailnet AI proxy; fall back to OpenAI without Tailscale.
  defaultProvider = if tailscale then "moonshotai" else "openai";
  defaultModel = if tailscale then "kimi-k3" else "gpt-5.6-sol";
}
