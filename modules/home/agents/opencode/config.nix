{
  pkgs,
  lib,
  gateways,
  access,
  policy,
  model,
  smallModel,
  mcpServers,
}:
{
  "$schema" = "https://opencode.ai/v2/config.json";
  inherit model;
  # Session titles are OpenCode's small-model task.
  agents.title.model = smallModel;
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
        cfAccessIdPath = access.idPath;
        cfAccessSecretPath = access.secretPath;
        # The plugin reaches the public origins only.
        gateways = lib.mapAttrsToList (
          id: gateway: removeAttrs gateway [ "relayPort" ] // { inherit id; }
        ) gateways;
        # /bin/cat does not exist on NixOS.
        cat = "${pkgs.coreutils}/bin/cat";
        # The cluster's SearXNG, in the gateways' Cloudflare Access application.
        searchUrl = "https://search.clusters.work";
      };
    }
  ];
  # Registered by the plugin above; models with hosted search do not see it.
  websearch.provider = "searxng";
  mcp.servers = mcpServers;

  permissions =
    map (resource: {
      action = "external_directory";
      inherit resource;
      effect = "allow";
    }) (policy.readable ++ [ "/tmp/**" ])
    ++ map (resource: {
      action = "edit";
      inherit resource;
      effect = "deny";
    }) policy.readOnly;

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
  }) (lib.attrNames gateways);
}
