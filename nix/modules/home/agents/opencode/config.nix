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
  plugin = lib.optionals proxyAccounts [
    # Discover the proxy catalog from its OpenAI-compatible /models endpoint.
    "opencode-models-discovery@1.3.1"
  ];
  default_agent = "plan";
  share = "disabled";
  disabled_providers = [
    "opencode" # disable Opencode Zen
  ];

  server = {
    port = 4096;
    hostname = "127.0.0.1";
  };

  permission = {
    external_directory = {
      "/nix/store/**" = "allow";
      "/tmp/**" = "allow";
    };
    edit."/nix/store/**" = "deny";
  };

  provider = {
    # OpenCode Go subscription (https://opencode.ai/zen/go); always available.
    opencode-go = {
      options.apiKey = "{file:${config.age.secrets.opencode-api-key.path}}";
      whitelist = [
        "deepseek-v4-flash"
        "deepseek-v4-pro"
        "grok-4.5"
        "gpt-5.6-luna"
        "qwen3.8-max"
      ];
    };
  }
  # Providers billed per API key; only wired when API accounts are enabled.
  // lib.optionalAttrs apiAccounts {
    openai = {
      options.apiKey = "{file:${config.age.secrets.openai-api-key.path}}";
      whitelist = [
        "gpt-5.6-sol"
        "gpt-5.6-terra"
        "gpt-5.6-luna"
      ];
    };
    anthropic = {
      options.apiKey = "{file:${config.age.secrets.anthropic-api-key.path}}";
      whitelist = [
        "claude-opus-5"
        "claude-sonnet-5"
        "claude-fable-5"
      ];
    };
    deepseek = {
      options.apiKey = "{file:${config.age.secrets.deepseek-api-key.path}}";
      whitelist = [
        "deepseek-v4-flash"
        "deepseek-v4-pro"
      ];
    };
  }
  # The AI proxy lives on the tailnet; only reachable with Tailscale.
  // lib.optionalAttrs proxyAccounts {
    ai-proxy = {
      name = "AI Proxy";
      npm = "@ai-sdk/openai-compatible";
      whitelist = [
        "kimi-k3"
        "gpt-5.6-sol"
        "gpt-5.6-terra"
        "gemini-3.6-flash"
        "gemini-3.1-pro-preview"
      ];
      options = {
        baseURL = "https://ai-proxy.at-basking.ts.net/v1";
        apiKey = "{file:${config.age.secrets.ai-proxy-api-key.path}}";
        modelsDiscovery = {
          enabled = true;
          timeoutMs = 10000;
          modelInfoFormat = "models.dev";
          smartModelName = true;
        };
      };
    };
  };
}
