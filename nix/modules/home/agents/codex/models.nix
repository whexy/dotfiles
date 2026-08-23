# codex provider/model entries for the fzf picker wrapper.
# codex has no model env var; the model is passed with -m. Auth uses
# OPENAI_API_KEY (+ OPENAI_BASE_URL for the proxy), and
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
    env.OPENAI_BASE_URL = "https://ai-proxy.at-basking.ts.net/v1";
    secrets.OPENAI_API_KEY = config.age.secrets.ai-proxy-api-key.path;
    args = [
      "-c"
      ''preferred_auth_method="apikey"''
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
  # OpenCode Go subscription (https://opencode.ai/zen/go); always
  # available. Codex only supports the Responses wire protocol
  # (wire_api "chat" was removed); the Go /v1/responses endpoint serves
  # every Go model regardless of the documented per-model endpoint.
  # A custom provider is defined via -c overrides and reads its key from
  # OPENCODE_GO_API_KEY.
  opencodeGo = model: {
    label = "opencode-go/${model}";
    secrets.OPENCODE_GO_API_KEY = config.age.secrets.opencode-api-key.path;
    args = [
      "-c"
      ''model_provider="opencode-go"''
      "-c"
      ''model_providers.opencode-go.base_url="https://opencode.ai/zen/go/v1"''
      "-c"
      ''model_providers.opencode-go.wire_api="responses"''
      "-c"
      ''model_providers.opencode-go.env_key="OPENCODE_GO_API_KEY"''
      "-m"
      model
    ];
  };
in
[ { label = "default (ChatGPT login)"; } ]
++ map opencodeGo [
  "grok-4.5"
  "gpt-5.6-luna"
  "deepseek-v4-pro"
  "deepseek-v4-flash"
]
++ lib.optionals proxyAccounts (
  map proxy [
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
