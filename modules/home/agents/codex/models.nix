# Native Codex provider configuration; credentials are loaded at launch.
# Separate API providers avoid changing the user's saved ChatGPT login.
{
  config,
  lib,
  apiAccounts,
  proxyAccounts,
  proxy,
}:
let
  # The proxy sits behind Cloudflare Access. `env_http_headers` maps a
  # header onto the env var holding its value, so the picker exports the
  # service token and codex reads it at request time.
  #
  aiProxy = model: {
    label = "ai-proxy/${model}";
    secrets = proxy.cfAccessSecrets // {
      OPENAI_API_KEY = proxy.apiKeyPath;
    };
    settings = {
      inherit model;
      model_provider = "dotfiles-proxy";
      model_providers.dotfiles-proxy = {
        name = "CLIProxyAPI";
        base_url = "${proxy.baseUrl}/v1";
        wire_api = "responses";
        requires_openai_auth = false;
        env_key = "OPENAI_API_KEY";
        env_http_headers = proxy.cfAccessHeaderEnv;
      };
    };
  };
  openai = model: {
    label = "openai/${model}";
    secrets.OPENAI_API_KEY = config.age.secrets.openai-api-key.path;
    settings = {
      inherit model;
      model_provider = "dotfiles-openai";
      model_providers.dotfiles-openai = {
        name = "OpenAI API";
        base_url = "https://api.openai.com/v1";
        wire_api = "responses";
        requires_openai_auth = false;
        env_key = "OPENAI_API_KEY";
      };
    };
  };
in
[ { label = "default (ChatGPT login)"; } ]
++ lib.optionals proxyAccounts (
  map aiProxy [
    "claude-opus-5-5"
    "claude-fable-5-1"
    "gpt-6-astra"
    "gpt-5.6-sol"
    "gpt-5.6-terra"
    "kimi-k3"
  ]
)
++ lib.optionals apiAccounts (
  map openai [
    "gpt-6-astra"
    "gpt-5.6-sol"
    "gpt-5.6-terra"
    "gpt-5.6-luna"
  ]
)
