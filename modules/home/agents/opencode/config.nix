{
  lib,
  proxy,
  defaults,
  mcp,
}:
let
  providers = {
    cliproxyapi = {
      name = "CLIProxyAPI";
      # The fallback for models absent from models.dev. The URL is `api`
      # rather than `options.baseURL`, which would override the per-model
      # URL the plugin sets for SDKs with other path conventions.
      npm = "@ai-sdk/openai-compatible";
      api = "${proxy.baseUrl}/v1";
      options = {
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
