# codex provider/model entries for the fzf picker wrapper.
# codex has no model env var; the model is passed with -m. Auth uses
# OPENAI_API_KEY, and
# preferred_auth_method stops a ChatGPT login from shadowing the key.
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
  # The whole map must be one inline table: `-c` splits a dotted path on
  # every `.` without honouring TOML quoting, so a quoted header segment
  # silently lands under the wrong key and the headers never get sent.
  # Assigning `env_http_headers` also drops the provider's implicit
  # `env_key`, so it is stated explicitly.
  cfAccessHeaders = "model_providers.cliproxyapi.env_http_headers={${
    lib.concatStringsSep "," (
      lib.mapAttrsToList (
        header: var: "${builtins.toJSON header}=${builtins.toJSON var}"
      ) proxy.cfAccessHeaderEnv
    )
  }}";
  aiProxy = model: {
    label = "ai-proxy/${model}";
    secrets = proxy.cfAccessSecrets // {
      OPENAI_API_KEY = proxy.apiKeyPath;
    };
    args = [
      "-c"
      ''preferred_auth_method="apikey"''
      "-c"
      ''model_provider="cliproxyapi"''
      "-c"
      ''model_providers.cliproxyapi.name="CLIProxyAPI"''
      "-c"
      ''model_providers.cliproxyapi.base_url="${proxy.baseUrl}/v1"''
      "-c"
      ''model_providers.cliproxyapi.wire_api="responses"''
      "-c"
      "model_providers.cliproxyapi.requires_openai_auth=true"
      "-c"
      ''model_providers.cliproxyapi.env_key="OPENAI_API_KEY"''
      "-c"
      cfAccessHeaders
      "-m"
      model
    ];
  };
  openai = model: {
    label = "openai/${model}";
    secrets.OPENAI_API_KEY = config.age.secrets.openai-api-key.path;
    args = [
      "-c"
      ''preferred_auth_method="apikey"''
      "-m"
      model
    ];
  };
in
[ { label = "default (ChatGPT login)"; } ]
++ lib.optionals proxyAccounts (
  map aiProxy [
    "claude-opus-5"
    "claude-fable-5-1"
    "gpt-6-astra"
    "gpt-5.6-sol"
    "gpt-5.6-terra"
    "kimi-k3"
    "devin/swe-2"
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
