{
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
{
  "$schema" = "https://opencode.ai/config.json";
  # kimi-k3 goes through the tailnet AI proxy; fall back to OpenCode Go without Tailscale.
  model = if proxyAccounts then "moonshotai/kimi-k3" else "opencode-go/deepseek-v4-flash";
  autoupdate = false;
  default_agent = "plan";
  share = "disabled";
  disabled_providers = [
    "opencode" # disable Opencode Zen
  ];

  permissions = [
    {
      action = "external_directory";
      resource = "/nix/store/*";
      effect = "allow";
    }
    {
      action = "external_directory";
      resource = "/tmp/*";
      effect = "allow";
    }
    {
      action = "edit";
      resource = "/nix/store/*";
      effect = "deny";
    }
  ];

  providers = {
    # OpenCode Go subscription (https://opencode.ai/zen/go); always available.
    opencode-go = {
      settings.apiKey = "{file:${config.age.secrets.opencode-api-key.path}}";
    };
  }
  # Providers billed per API key; only wired when API accounts are enabled.
  // lib.optionalAttrs apiAccounts {
    openai = {
      settings.apiKey = "{file:${config.age.secrets.openai-api-key.path}}";
    };
    anthropic = {
      settings.apiKey = "{file:${config.age.secrets.anthropic-api-key.path}}";
    };
    deepseek = {
      settings.apiKey = "{file:${config.age.secrets.deepseek-api-key.path}}";
    };
  }
  # The AI proxy lives on the tailnet; only reachable with Tailscale.
  // lib.optionalAttrs proxyAccounts {
    moonshotai = {
      settings = {
        baseURL = "https://ai-proxy.at-basking.ts.net/v1";
        apiKey = "{file:${config.age.secrets.ai-proxy-api-key.path}}";
      };
    };
    google = {
      settings = {
        baseURL = "https://ai-proxy.at-basking.ts.net/v1beta";
        apiKey = "{file:${config.age.secrets.ai-proxy-api-key.path}}";
      };
    };
  };
}
