{
  lib,
  proxyAccounts,
  apiAccounts,
  proxy,
  defaults,
  mcp,
  models,
}:
let
  # "provider/model" -> { provider, model }; model ids may contain slashes.
  split =
    id:
    let
      parts = lib.splitString "/" id;
    in
    {
      provider = lib.head parts;
      model = lib.concatStringsSep "/" (lib.tail parts);
    };
  # The shared roster plus the default models, which the fallback tier picks
  # from outside the roster.
  roster = map split (
    map (model: model.id) models
    ++ [
      defaults.default
      defaults.cheap
    ]
  );
  modelsOf =
    provider:
    lib.unique (map (entry: entry.model) (lib.filter (entry: entry.provider == provider) roster));

  # The launcher exports every key; agenix paths are shell fragments that
  # `{file:...}` cannot expand.
  keyed = provider: env: {
    options.apiKey = "{env:${env}}";
    whitelist = modelsOf provider;
  };

  # Providers the roster does not use stay out of enabled_providers.
  providers =
    lib.filterAttrs (_: provider: provider.whitelist != [ ]) (
      {
        # The OpenRouter key is present on every host.
        openrouter = keyed "openrouter" "OPENROUTER_API_KEY";
      }
      // lib.optionalAttrs apiAccounts {
        openai = keyed "openai" "OPENAI_API_KEY";
        anthropic = keyed "anthropic" "ANTHROPIC_API_KEY";
      }
    )
    // lib.optionalAttrs proxyAccounts {
      ai-proxy = {
        name = "AI Proxy";
        npm = "@ai-sdk/openai-compatible";
        options = {
          baseURL = "${proxy.baseUrl}/v1";
          apiKey = "{env:AI_PROXY_API_KEY}";
          headers = lib.mapAttrs (_: env: "{env:${env}}") proxy.cfAccessHeaderEnv;
        };
        # A custom provider only offers the models it declares; plugins/ai-proxy.js
        # fills in their metadata.
        models = lib.genAttrs (modelsOf "ai-proxy") (_: { });
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
  # Keeps providers auto-detected from ambient credentials (and OpenCode Zen)
  # out of the model list, so it matches pi's.
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
