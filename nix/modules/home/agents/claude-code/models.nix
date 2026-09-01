# claude-code provider/model entries for the fzf picker wrapper.
# claude reads ANTHROPIC_MODEL and authenticates with ANTHROPIC_API_KEY.
# Compatible providers additionally require ANTHROPIC_BASE_URL.
{
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
let
  # Claude models keep Claude Code's native family resolution. OpenAI
  # models map Claude's cost/capability tiers onto the proxy catalog.
  # Other compatible models cannot satisfy those aliases, so every role
  # is pinned to the selected model. Unknown model window enforcement is
  # disabled for non-Claude IDs so the API remains the source of truth.
  anthropicEnv = model: {
    ANTHROPIC_MODEL = model;
  };
  select =
    model:
    anthropicEnv model
    // {
      CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1";
    };
  mapOpenAI =
    model:
    select model
    // {
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "gpt-5.6-luna";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "gpt-5.6-terra";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "gpt-5.6-sol";
      ANTHROPIC_DEFAULT_FABLE_MODEL = "gpt-5.6-sol";
    };
  pin =
    model:
    select model
    // {
      ANTHROPIC_DEFAULT_HAIKU_MODEL = model;
      ANTHROPIC_DEFAULT_SONNET_MODEL = model;
      ANTHROPIC_DEFAULT_OPUS_MODEL = model;
      ANTHROPIC_DEFAULT_FABLE_MODEL = model;
      CLAUDE_CODE_SUBAGENT_MODEL = model;
    };
  # The tailnet AI proxy (CLIProxyAPI) exposes an Anthropic-compatible
  # endpoint serving its whole catalog; Claude Code appends /v1/messages
  # to the base URL. It accepts the key in the x-api-key header.
  proxy = mapping: model: {
    label = "ai-proxy/${model}";
    env = mapping model // {
      ANTHROPIC_BASE_URL = "https://ai-proxy.at-basking.ts.net";
    };
    secrets.ANTHROPIC_API_KEY = config.age.secrets.ai-proxy-api-key.path;
  };
  anthropic = model: {
    label = "anthropic/${model}";
    env.ANTHROPIC_MODEL = model;
    secrets.ANTHROPIC_API_KEY = config.age.secrets.anthropic-api-key.path;
  };
  # OpenRouter serves an Anthropic-compatible endpoint; the base URL omits
  # /v1 because Claude Code appends /v1/messages. GLM emits thinking blocks
  # with empty signatures, which OpenRouter accepts on replay.
  openrouter = model: {
    label = "openrouter/${model}";
    env = pin model // {
      ANTHROPIC_BASE_URL = "https://openrouter.ai/api";
    };
    secrets.ANTHROPIC_API_KEY = config.age.secrets.openrouter-api-key.path;
  };
  # OpenCode Go subscription (https://opencode.ai/zen/go); always
  # available. Claude Code speaks the Anthropic Messages API; verified
  # against /v1/messages (x-api-key auth): qwen and deepseek models
  # answer, grok-4.6, gpt-5.6-luna, and glm-5.3-flash are rejected.
  opencodeGo = model: {
    label = "opencode-go/${model}";
    env = pin model // {
      ANTHROPIC_BASE_URL = "https://opencode.ai/zen/go";
    };
    secrets.ANTHROPIC_API_KEY = config.age.secrets.opencode-api-key.path;
  };
  modelEntries =
    map opencodeGo [
      "qwen3.8-max"
      "deepseek-v4-pro"
      "deepseek-v4-flash"
    ]
    ++ lib.optionals apiAccounts (
      map openrouter [
        "z-ai/glm-5.3-flash"
      ]
    )
    ++ lib.optionals proxyAccounts (
      map (proxy anthropicEnv) [
        "claude-opus-5"
        "claude-fable-5-1"
      ]
      ++ map (proxy mapOpenAI) [
        "gpt-5.6-sol"
        "gpt-5.6-terra"
        "gpt-5.6-luna"
      ]
      ++ map (proxy pin) [
        "kimi-k3"
        "gemini-3.7-flash"
      ]
    )
    ++ lib.optionals apiAccounts (
      map anthropic [
        "claude-opus-5"
        "claude-sonnet-5"
        "claude-fable-5-1"
      ]
    );
in
[ { label = "default (claude.ai login)"; } ]
++ modelEntries
++ [
  # Fusion mode: the main pick fixes the provider (endpoint + key), and
  # each remaining role is then picked from that provider's models only.
  # Roles override the ANTHROPIC_DEFAULT_*_MODEL vars; the main model
  # itself comes from the picked candidate's ANTHROPIC_MODEL.
  {
    label = "fusion (one model per role)";
    fusion = {
      roles = [
        {
          name = "fable";
          prompt = "FABLE model";
          export = "ANTHROPIC_DEFAULT_FABLE_MODEL";
        }
        {
          name = "opus";
          prompt = "OPUS model";
          export = "ANTHROPIC_DEFAULT_OPUS_MODEL";
        }
        {
          name = "sonnet";
          prompt = "SONNET model";
          export = "ANTHROPIC_DEFAULT_SONNET_MODEL";
        }
        {
          name = "haiku";
          prompt = "HAIKU model";
          export = "ANTHROPIC_DEFAULT_HAIKU_MODEL";
        }
      ];
      candidates = modelEntries;
    };
  }
]
