# claude-code provider/model entries for the fzf picker wrapper.
# claude reads ANTHROPIC_MODEL and authenticates with ANTHROPIC_API_KEY.
# Compatible providers additionally require ANTHROPIC_BASE_URL.
{
  proxy,
}:
let
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
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "gpt-6-luna";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "gpt-6-sol";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "gpt-6-sol";
      ANTHROPIC_DEFAULT_FABLE_MODEL = "gpt-6-astra";
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
  # CLIProxyAPI exposes an Anthropic-compatible endpoint
  # serving its whole catalog; Claude Code appends /v1/messages to the
  # base URL. It accepts the key in the x-api-key header.
  #
  # The endpoint sits behind Cloudflare Access, whose service token goes
  # in ANTHROPIC_CUSTOM_HEADERS: `Name: Value` pairs, newline-separated.
  aiProxyDefault = {
    label = "cliproxyapi (default models)";
    env = {
      ANTHROPIC_BASE_URL = proxy.baseUrl;
    };
    secrets = proxy.cfAccessSecrets // {
      ANTHROPIC_API_KEY = proxy.apiKeyPath;
    };
    secretHeaders = proxy.cfAccessHeaderEnv;
  };
  aiProxy =
    mapping: model:
    aiProxyDefault
    // {
      label = "cliproxyapi/${model}";
      env = aiProxyDefault.env // mapping model;
    };
  modelEntries =
    map (aiProxy anthropicEnv) [
      "claude-opus-5-5"
      "claude-sonnet-5"
      "claude-fable-5-1"
    ]
    ++ map (aiProxy mapOpenAI) [
      "gpt-6-astra"
      "gpt-6-sol"
      "gpt-6-luna"
    ]
    ++ map (aiProxy pin) [
      "gemini-3.8-flash"
      "grok-4.7"
    ];
in
[ aiProxyDefault ]
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
