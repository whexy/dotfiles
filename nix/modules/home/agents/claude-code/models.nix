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
  # Claude Code resolves several internal roles to model aliases, not
  # the selected session model: the Bash permission classifier uses the
  # sonnet alias (claude-sonnet-5 by default, opus alias as fallback),
  # background tasks use the haiku alias (ANTHROPIC_SMALL_FAST_MODEL is
  # deprecated in favor of ANTHROPIC_DEFAULT_HAIKU_MODEL), and subagents
  # run their own resolution (built-in Explore hardcodes a haiku ID).
  # Catalog endpoints serve neither the default claude-* IDs nor the
  # aliases, so every role is pinned to the selected model; otherwise
  # the classifier blocks every Bash call and subagents fall back to a
  # claude.ai login prompt. Unknown model window enforcement is off so
  # context usage comes from the API instead of an assumed 200k window.
  pinAll = model: {
    ANTHROPIC_MODEL = model;
    ANTHROPIC_SMALL_FAST_MODEL = model;
    ANTHROPIC_DEFAULT_HAIKU_MODEL = model;
    ANTHROPIC_DEFAULT_SONNET_MODEL = model;
    ANTHROPIC_DEFAULT_OPUS_MODEL = model;
    ANTHROPIC_DEFAULT_FABLE_MODEL = model;
    CLAUDE_CODE_SUBAGENT_MODEL = model;
    CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1";
  };
  # The tailnet AI proxy (CLIProxyAPI) exposes an Anthropic-compatible
  # endpoint serving its whole catalog; Claude Code appends /v1/messages
  # to the base URL.
  proxy = model: {
    label = "ai-proxy/${model}";
    env = pinAll model // {
      ANTHROPIC_BASE_URL = "https://ai-proxy.at-basking.ts.net";
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
  # answer, grok-4.5 and gpt-5.6-luna are rejected.
  opencodeGo = model: {
    label = "opencode-go/${model}";
    env = pinAll model // {
      ANTHROPIC_BASE_URL = "https://opencode.ai/zen/go";
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
