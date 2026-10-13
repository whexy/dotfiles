# muse provider/model entries for the selector wrapper.
#
# Muse Code only talks to its Meta provider, which posts to the OpenAI
# Responses API CLIProxyAPI serves. It first fetches a model catalog from
# `{origin}/muse-code/models`, a path CLIProxyAPI does not have, and refuses
# to start when that fails, so the endpoint is the loopback muse-shim: it
# serves the catalog from the proxy's `/v1/models` and forwards the rest,
# adding the Cloudflare Access headers. The API key Muse sends is the
# proxy's own, which the shim forwards untouched.
{
  proxy,
  defaults,
  shimBaseUrl,
}:
let
  endpoint = {
    base_url = shimBaseUrl;
    auth = "bearer";
  };
  aiProxyDefault = {
    label = "cliproxyapi (default models)";
    secrets = {
      META_API_KEY = proxy.apiKeyPath;
    };
    settings = {
      model = defaults.defaultModel;
      endpoint_transport = endpoint;
    };
  };
  # One entry per model the proxy serves when the picker opens. Discovery
  # talks to CLIProxyAPI directly; the shim only exists for Muse's own
  # catalog fetch at runtime.
  aiProxyModels = {
    label = "cliproxyapi";
    secrets = proxy.cfAccessSecrets // {
      META_API_KEY = proxy.apiKeyPath;
    };
    secretHeaders = proxy.cfAccessHeaderEnv;
    settings = {
      endpoint_transport = endpoint;
    };
    discover = {
      url = "${proxy.baseUrl}/v1/models";
      keyEnv = "META_API_KEY";
      modelEnv = [ "MUSE_MODEL" ];
    };
  };
in
[
  aiProxyDefault
  aiProxyModels
]
