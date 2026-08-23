# claude-code provider/model entries for the fzf picker wrapper.
# claude reads ANTHROPIC_MODEL, authenticating with ANTHROPIC_API_KEY
# (direct API) or ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN (proxy).
{
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
let
  # The tailnet AI proxy (CLIProxyAPI) exposes an Anthropic-compatible
  # endpoint serving its whole catalog; Claude Code appends /v1/messages
  # to the base URL. ANTHROPIC_SMALL_FAST_MODEL is pinned because the
  # proxy does not serve the default haiku background model, and unknown
  # model window enforcement is off so context usage comes from the API
  # instead of an assumed 200k window.
  proxy = model: {
    label = "ai-proxy/${model}";
    env = {
      ANTHROPIC_BASE_URL = "https://ai-proxy.at-basking.ts.net";
      ANTHROPIC_MODEL = model;
      ANTHROPIC_SMALL_FAST_MODEL = model;
      CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1";
    };
    secrets.ANTHROPIC_AUTH_TOKEN = config.age.secrets.ai-proxy-api-key.path;
  };
  anthropic = model: {
    label = "anthropic/${model}";
    env.ANTHROPIC_MODEL = model;
    secrets.ANTHROPIC_API_KEY = config.age.secrets.anthropic-api-key.path;
  };
  # OpenCode Go subscription (https://opencode.ai/zen/go); always
  # available. Claude Code speaks the Anthropic Messages API; verified
  # against /v1/messages (x-api-key auth): qwen and deepseek models
  # answer, grok-4.5 and gpt-5.6-luna are rejected. Window enforcement
  # is disabled for the same reason as the proxy entries.
  opencodeGo = model: {
    label = "opencode-go/${model}";
    env = {
      ANTHROPIC_BASE_URL = "https://opencode.ai/zen/go";
      ANTHROPIC_MODEL = model;
      ANTHROPIC_SMALL_FAST_MODEL = model;
      CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1";
    };
    secrets.ANTHROPIC_API_KEY = config.age.secrets.opencode-api-key.path;
  };
in
[ { label = "default (claude.ai login)"; } ]
++ map opencodeGo [
  "qwen3.8-max"
  "deepseek-v4-pro"
  "deepseek-v4-flash"
]
++ lib.optionals proxyAccounts (
  map proxy [
    "kimi-k3"
    "gpt-5.6-sol"
    "gpt-5.6-terra"
    "gemini-3.1-pro-preview"
    "gemini-3.6-flash"
  ]
)
++ lib.optionals apiAccounts (
  map anthropic [
    "claude-opus-5"
    "claude-sonnet-5"
    "claude-fable-5"
  ]
)
