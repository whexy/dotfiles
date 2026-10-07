# claude-code provider/model entries for the fzf picker wrapper.
# claude reads ANTHROPIC_MODEL and authenticates with ANTHROPIC_API_KEY.
# Compatible providers additionally require ANTHROPIC_BASE_URL.
{
  proxy,
}:
let
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
  # One entry per model the proxy serves when the picker opens. The picked
  # model fills every role, so Claude Code never falls back to a built-in
  # role default the proxy may not serve.
  aiProxyModels = aiProxyDefault // {
    label = "cliproxyapi";
    env = aiProxyDefault.env // {
      CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1";
    };
    discover = {
      url = "${proxy.baseUrl}/v1/models";
      keyEnv = "ANTHROPIC_API_KEY";
      modelEnv = [
        "ANTHROPIC_MODEL"
        "CLAUDE_CODE_SUBAGENT_MODEL"
      ]
      ++ map (role: role.export) roles;
    };
  };
in
[
  aiProxyDefault
  aiProxyModels
  # Fusion mode: the main pick fixes the provider (endpoint + key), and
  # each remaining role is then picked from that provider's models only.
  # Roles override the ANTHROPIC_DEFAULT_*_MODEL vars; the main model
  # itself comes from the picked candidate's ANTHROPIC_MODEL.
  {
    label = "fusion (one model per role)";
    fusion = {
      inherit roles;
      candidates = [ aiProxyModels ];
    };
  }
]
