# Home Manager file deployments for OpenCode: plugins and their data file.
{
  config,
  lib,
  proxyAccounts,
  baseURL,
}:
{
  # Deploy the notification plugin so it is auto-loaded by OpenCode.
  ".config/opencode/plugins/notify.js".source = ./plugins/notify.js;
  # Model allow-list enforcement + AI proxy discovery (see models.nix).
  ".config/opencode/plugins/agent-models.js".source = ./plugins/agent-models.js;
  ".config/opencode/agent-models.json".text = builtins.toJSON (
    {
      allow = import ./models.nix;
    }
    // lib.optionalAttrs proxyAccounts {
      proxy = {
        id = "ai-proxy";
        inherit baseURL;
        keyFile = config.age.secrets.ai-proxy-api-key.path;
      };
    }
  );
}
