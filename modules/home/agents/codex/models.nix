{
  codexVersion,
  proxy,
}:
let
  # CLIProxyAPI sits behind Cloudflare Access. `env_http_headers` maps a
  # header onto the env var holding its value, so the picker exports the
  # service token and codex reads it at request time.
  #
  aiProxyDefault = {
    label = "cliproxyapi (default models)";
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
        requires_openai_auth = false;
        env_key = "OPENAI_API_KEY";
        env_http_headers = proxy.cfAccessHeaderEnv;
      };
    };
  };
  aiProxy =
    model:
    aiProxyDefault
    // {
      label = "cliproxyapi/${model}";
      settings = aiProxyDefault.settings // {
        inherit model;
      };
    };
in
[ aiProxyDefault ]
++ map aiProxy [
  "claude-opus-5-5"
  "claude-fable-5-1"
  "gpt-6-astra"
  "gpt-6-sol"
  "gemini-3.8-flash"
  "grok-4.7"
]
