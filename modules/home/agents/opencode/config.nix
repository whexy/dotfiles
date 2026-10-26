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
  agents.plan.disabled = true;
  default_agent = "build";
  update = "disable";
  share = "disabled";
  # The plugin registers a provider per gateway, each with the gateway's
  # live model list from its Codex model catalog. It reads the agenix
  # secrets itself because OpenCode's shared background server outlives the
  # launch that started it.
  plugins = [
    {
      package = "${./plugins/proxy}";
      options = {
        inherit (proxy) cfAccessIdPath cfAccessSecretPath;
        gateways = lib.mapAttrsToList (id: gateway: gateway // { inherit id; }) proxy.gateways;
        # /bin/cat does not exist on NixOS.
        cat = "${pkgs.coreutils}/bin/cat";
        # The cluster's SearXNG, in the gateways' Cloudflare Access application.
        searchUrl = "https://search.clusters.work";
      };
    }
  ];
  # Registered by the plugin above; models with hosted search do not see it.
  websearch.provider = "searxng";
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
  ]
  ++ map (id: {
    action = "provider.use";
    resource = id;
    effect = "allow";
  }) (lib.attrNames proxy.gateways);
}
