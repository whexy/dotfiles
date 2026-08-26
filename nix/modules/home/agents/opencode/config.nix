{
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
{
  "$schema" = "https://opencode.ai/config.json";
  # kimi-k3 goes through the tailnet AI proxy; fall back to OpenCode Go without Tailscale.
  model = if proxyAccounts then "ai-proxy/kimi-k3" else "opencode-go/deepseek-v4-flash";
  autoupdate = false;
  default_agent = "plan";
  share = "disabled";
  disabled_providers = [
    "opencode" # disable Opencode Zen
  ];

  permission = {
    external_directory = {
      "/nix/store/**" = "allow";
      "/tmp/**" = "allow";
    };
    edit."/nix/store/**" = "deny";
  };

  provider = {
    # OpenCode Go subscription (https://opencode.ai/zen/go); always available.
    # Model visibility is enforced by plugins/agent-models.js; V2 dropped
    # provider whitelist/blacklist.
    opencode-go.options.apiKey = "{file:${config.age.secrets.opencode-api-key.path}}";
  }
  # Providers billed per API key; only wired when API accounts are enabled.
  // lib.optionalAttrs apiAccounts {
    openai.options.apiKey = "{file:${config.age.secrets.openai-api-key.path}}";
    anthropic.options.apiKey = "{file:${config.age.secrets.anthropic-api-key.path}}";
    deepseek.options.apiKey = "{file:${config.age.secrets.deepseek-api-key.path}}";
    openrouter.options.apiKey = "{file:${config.age.secrets.openrouter-api-key.path}}";
  }
  # The AI proxy lives on the tailnet; only reachable with Tailscale. Its
  # catalog is discovered from /models by plugins/agent-models.js; the proxy
  # filters that list server-side.
  // lib.optionalAttrs proxyAccounts {
    ai-proxy = {
      name = "AI Proxy";
      npm = "@ai-sdk/openai-compatible";
      options = {
        baseURL = "https://ai-proxy.at-basking.ts.net/v1";
        apiKey = "{file:${config.age.secrets.ai-proxy-api-key.path}}";
      };
    };
  };
}
