# codex provider/model entries for the fzf picker wrapper.
# codex has no model env var; the model is passed with -m. Auth uses
# OPENAI_API_KEY, and
# preferred_auth_method stops a ChatGPT login from shadowing the key.
{
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
let
  proxy = model: {
    label = "ai-proxy/${model}";
    secrets.OPENAI_API_KEY = config.age.secrets.ai-proxy-api-key.path;
    args = [
      "-c"
      ''preferred_auth_method="apikey"''
      "-c"
      ''model_provider="cliproxyapi"''
      "-c"
      ''model_providers.cliproxyapi.name="CLIProxyAPI"''
      "-c"
      ''model_providers.cliproxyapi.base_url="https://ai-proxy.at-basking.ts.net/v1"''
      "-c"
      ''model_providers.cliproxyapi.wire_api="responses"''
      "-c"
      "model_providers.cliproxyapi.requires_openai_auth=true"
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
  map proxy [
    "claude-opus-5"
    "claude-fable-5-1"
    "gpt-5.6-sol"
    "gpt-5.6-terra"
    "kimi-k3"
  ]
)
++ lib.optionals apiAccounts (
  map openai [
    "gpt-5.6-sol"
    "gpt-5.6-terra"
    "gpt-5.6-luna"
  ]
)
