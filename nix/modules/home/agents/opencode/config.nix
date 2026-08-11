{
  config,
  lib,
  osConfig,
}:
let
  tailscale = osConfig != null && osConfig.dotfiles.network.tailscale.enable;
in
{
  "$schema" = "https://opencode.ai/config.json";
  # kimi-k3 goes through the tailnet AI proxy; fall back to OpenAI without Tailscale.
  model = if tailscale then "moonshotai/kimi-k3" else "opencode-go/deepseek-v4-flash";
  autoupdate = false;
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
      ];
    };
    # OpenCode Go subscription (https://opencode.ai/zen/go).
    opencode-go = {
      options.apiKey = "{file:${config.age.secrets.opencode-api-key.path}}";
      whitelist = [
        "deepseek-v4-flash"
        "grok-4.5"
        "gpt-5.6-luna"
        "qwen3.8-max"
      ];
    };
  }
  # The AI proxy lives on the tailnet; only reachable with Tailscale.
  // lib.optionalAttrs tailscale {
    moonshotai = {
      options = {
        baseURL = "https://ai-proxy.at-basking.ts.net/v1";
        apiKey = "kfc-vivo-50";
      };
      whitelist = [
        "kimi-k3"
      ];
    };
    google = {
      options = {
        baseURL = "https://ai-proxy.at-basking.ts.net/v1beta";
        apiKey = "kfc-vivo-50";
      };
      whitelist = [
        "gemini-3.6-flash"
        "gemini-3.1-pro-preview"
      ];
    };
  };
}
