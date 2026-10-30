# muse provider/model entries for the selector wrapper.
#
# Muse Code only talks to its Meta provider, which posts to the OpenAI
# Responses API CLIProxyAPI serves, so every host uses the Meta subscription
# the proxy holds instead of signing in itself. Before it starts, Muse fetches
# a model catalog from `{origin}/muse-code/models`, which clusters-work routes
# to the proxy's own model list.
#
# The provider models Muse fetches that way always arrive hidden, so they
# never appear in its /models picker. The wrapper therefore declares the
# Meta models as visible rows in settings (`model_catalog`), rebuilt from the
# proxy's model list at every select; Muse composes those over the provider
# rows.
#
# agent-settings saves the credentials in Muse's own config rather than its
# environment: the key with `muse auth set`, the Cloudflare Access headers
# (`secretHeaders`) in `endpoint_transport.http_headers`.
{ proxy }:
let
  gateway = proxy.gateways.cliproxyapi;
  base = {
    secrets = proxy.cfAccessSecrets // {
      META_API_KEY = gateway.apiKeyPath;
    };
    secretHeaders = proxy.cfAccessHeaderEnv;
    settings.endpoint_transport = {
      base_url = "${gateway.baseUrl}/v1";
      # Muse withholds the key from any host but Meta's own unless the
      # settings pin bearer auth to this base URL.
      auth = "bearer";
    };
  };
in
[
  (
    base
    // {
      label = "cliproxyapi (default models)";
      settings = base.settings // {
        model = "muse-wonder-1.0";
      };
    }
  )
  # One entry per model the subscription serves when the picker opens.
  (
    base
    // {
      label = "cliproxyapi";
      discover = {
        url = "${gateway.baseUrl}/v1/models";
        keyEnv = "META_API_KEY";
        modelEnv = [ "MUSE_MODEL" ];
        owner = "meta";
      };
    }
  )
]
