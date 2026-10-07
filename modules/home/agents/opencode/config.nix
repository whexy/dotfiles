{
  lib,
  proxyAccounts,
  apiAccounts,
  proxy,
  defaults,
  mcp,
}:
let
  # The launcher exports every key; agenix paths are shell fragments that
  # `{file:...}` cannot expand.
  keyed = env: {
    options.apiKey = "{env:${env}}";
  };

  providers = {
    # The OpenRouter key is present on every host.
    openrouter = keyed "OPENROUTER_API_KEY";
  }
  // lib.optionalAttrs apiAccounts {
    openai = keyed "OPENAI_API_KEY";
    anthropic = keyed "ANTHROPIC_API_KEY";
  }
  // lib.optionalAttrs proxyAccounts {
    ai-proxy = {
      name = "AI Proxy";
      npm = "@ai-sdk/openai-compatible";
      options = {
        baseURL = "${proxy.baseUrl}/v1";
        apiKey = "{env:AI_PROXY_API_KEY}";
        headers = lib.mapAttrs (_: env: "{env:${env}}") proxy.cfAccessHeaderEnv;
      };
      # The plugin discovers the proxy's live model list at startup.
      models = { };
    };
  };

  # Shared servers are written in Claude's shape: `url` for remote, `command`
  # plus `args` for local.
  toMcp =
    server:
    if server ? url then
      {
        type = "remote";
        inherit (server) url;
      }
      // lib.optionalAttrs (server ? headers) { inherit (server) headers; }
    else
      {
        type = "local";
        command = [ server.command ] ++ server.args or [ ];
      }
      // lib.optionalAttrs (server ? env) { environment = server.env; };
in
{
  "$schema" = "https://opencode.ai/config.json";
  model = defaults.default;
  small_model = defaults.cheap;
  autoupdate = false;
  default_agent = "plan";
  share = "disabled";
  # Keep providers auto-detected from ambient credentials (and OpenCode Zen)
  # out of the configured provider set.
  enabled_providers = lib.attrNames providers;
  provider = providers;
  mcp = lib.mapAttrs (_: toMcp) mcp.servers;

  permission = {
    external_directory = {
      "/nix/store/**" = "allow";
      "/tmp/**" = "allow";
    };
    edit."/nix/store/**" = "deny";
  };
}
