{
  codexVersion,
  proxy,
}:
# Codex discovers the proxy's models itself through `model_catalog_url`, so
# its own model picker lists them; this entry only configures the provider.
# The native login entry clears the provider so Codex uses its saved ChatGPT
# login. It stays after the proxy entry, which removed selections migrate to.
[
  {
    label = "cliproxyapi (default models)";
    # CLIProxyAPI sits behind Cloudflare Access. `env_http_headers` maps a
    # header onto the env var holding its value, so the picker exports the
    # service token and codex reads it at request time.
    secrets = proxy.cfAccessSecrets // {
      OPENAI_API_KEY = proxy.apiKeyPath;
    };
    settings = {
      model_provider = "cliproxyapi";
      features.api_key_model_discovery = true;
      model_providers.cliproxyapi = {
        name = "CLIProxyAPI";
        base_url = "${proxy.baseUrl}/v1";
        model_catalog_url = "${proxy.baseUrl}/v1/models?client_version=${codexVersion}";
        wire_api = "responses";
        supports_websockets = true;
        requires_openai_auth = false;
        env_key = "OPENAI_API_KEY";
        env_http_headers = proxy.cfAccessHeaderEnv;
      };
    };
  }
  { label = "default (ChatGPT login)"; }
]
