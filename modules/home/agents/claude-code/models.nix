# Claude Code's entries in the agent-settings model picker.
# claude reads ANTHROPIC_MODEL and authenticates with ANTHROPIC_API_KEY.
# Compatible providers additionally require ANTHROPIC_BASE_URL.
{ lib, llmGateways }:
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
  # Both gateways expose an Anthropic-compatible endpoint serving their
  # whole catalog; Claude Code appends /v1/messages to the base URL. They
  # accept the key in the x-api-key header.
  #
  # The public endpoints sit behind Cloudflare Access, whose service token
  # goes in ANTHROPIC_CUSTOM_HEADERS: `Name: Value` pairs, newline-separated.
  gatewayEntries =
    id: gateway:
    let
      endpoint = llmGateways.routes.${id};
    in
    rec {
      default = endpoint.relayCheck // {
        label = "${id} (default models)";
        inherit (endpoint) replacedBaseUrls;
        env = {
          ANTHROPIC_BASE_URL = endpoint.baseUrl;
          # Context usage of a model Claude Code does not know comes from the
          # API instead of an assumed 200k window. That includes a gateway
          # model named at launch, as T3 Code's model picker does.
          CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1";
          # Claude Code lists the gateway's models in /model and reports them
          # at initialize, where T3 Code adds them to its Claude provider.
          CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
        };
        secrets = endpoint.secrets // {
          ANTHROPIC_API_KEY = gateway.apiKeyPath;
        };
        inherit (endpoint) secretHeaders;
      };
      # One entry per model the gateway serves when the picker opens. The
      # picked model fills every role, so Claude Code never falls back to a
      # built-in role default the gateway may not serve.
      models = default // {
        label = id;
        discover = {
          url = endpoint.catalogUrl;
          keyEnv = "ANTHROPIC_API_KEY";
          modelEnv = [
            "ANTHROPIC_MODEL"
            "CLAUDE_CODE_SUBAGENT_MODEL"
          ]
          ++ map (role: role.export) roles;
        };
      };
    };
  gateways = lib.attrValues (lib.mapAttrs gatewayEntries llmGateways.gateways);
in
lib.concatMap (gateway: [
  gateway.default
  gateway.models
]) gateways
++ [
  # Fusion mode: the main pick fixes the provider (endpoint + key), and
  # each remaining role is then picked from that provider's models only.
  # Roles override the ANTHROPIC_DEFAULT_*_MODEL vars; the main model
  # itself comes from the picked candidate's ANTHROPIC_MODEL.
  {
    label = "fusion (one model per role)";
    fusion = {
      inherit roles;
      candidates = map (gateway: gateway.models) gateways;
    };
  }
  # Native claude.ai OAuth login: clears every gateway override. It stays
  # after the CLIProxyAPI default, which removed selections migrate to.
  { label = "default (claude.ai login)"; }
]
