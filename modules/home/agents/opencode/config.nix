{
  pkgs,
  lib,
  proxy,
  defaults,
  mcp,
}:
let
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
  "$schema" = "https://opencode.ai/v2/config.json";
  model = defaults.default;
  # Session titles are OpenCode's small-model task.
  agents.title.model = defaults.cheap;
  default_agent = "plan";
  update = "disable";
  share = "disabled";
  # The plugin registers the provider and the proxy's live model list. It
  # reads the agenix secrets itself because OpenCode's shared background
  # server outlives the launch that started it.
  plugins = [
    {
      package = "${./plugins/cliproxyapi}";
      options = {
        inherit (proxy)
          baseUrl
          apiKeyPath
          cfAccessIdPath
          cfAccessSecretPath
          ;
        # /bin/cat does not exist on NixOS.
        cat = "${pkgs.coreutils}/bin/cat";
      };
    }
  ];
  mcp.servers = lib.mapAttrs (_: toMcp) mcp.servers;

  permissions = [
    {
      action = "external_directory";
      resource = "/nix/store/**";
      effect = "allow";
    }
    {
      action = "external_directory";
      resource = "/tmp/**";
      effect = "allow";
    }
    {
      action = "edit";
      resource = "/nix/store/**";
      effect = "deny";
    }
  ];

  # Keep providers auto-detected from ambient credentials (and OpenCode Zen)
  # out of the configured provider set.
  experimental.policies = [
    {
      action = "provider.use";
      resource = "*";
      effect = "deny";
    }
    {
      action = "provider.use";
      resource = "cliproxyapi";
      effect = "allow";
    }
  ];
}
