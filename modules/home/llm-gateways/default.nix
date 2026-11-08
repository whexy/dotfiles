# The model gateways agents reach: CLIProxyAPI and magpie.
#
# Both are published on the public internet behind one Cloudflare Access
# application, so every request needs its service-token headers
# (`dotfiles.cloudflareAccess.serviceToken`) in addition to the gateway's own
# API key. Homes with a tailnet relay (`relay`) reach their tailnet origins
# instead, where only the API key applies. The keys are agenix secrets; each
# consumer declares `secrets` in its own gate, reads the files at run time,
# and sends them its own way.
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.dotfiles.llmGateways;
  relay = config.dotfiles.tailnetRelay;
  access = config.dotfiles.cloudflareAccess.serviceToken;
  # agenix paths are shell fragments ("''${XDG_RUNTIME_DIR}/agenix/..." on
  # Linux, "$(getconf DARWIN_USER_TEMP_DIR)/agenix/..." on Darwin), so a
  # consumer expands them at run time.
  secretPath = name: config.age.secrets.${name}.path;
  gateway = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name.";
      };
      baseUrl = lib.mkOption {
        type = lib.types.str;
        description = "Public origin of the gateway's OpenAI- and Anthropic-compatible endpoints.";
      };
      tailnetUrl = lib.mkOption {
        type = lib.types.str;
        description = ''
          The gateway's tailnet origin, which serves the same endpoints with
          no Cloudflare Access in front.
        '';
      };
      apiKeyPath = lib.mkOption {
        type = lib.types.str;
        description = "agenix path of the gateway's API key.";
      };
      catalogPath = lib.mkOption {
        type = lib.types.str;
        description = ''
          Path of the gateway's Codex model catalog, whose records carry the
          display names, limits, and reasoning levels the OpenAI-shaped list
          omits. Agents list the gateway's models from it.
        '';
      };
      catalogUrl = lib.mkOption {
        type = lib.types.str;
        description = "The catalog on the public origin.";
      };
      qualifiedIds = lib.mkOption {
        type = lib.types.bool;
        description = "Whether model IDs are `<provider>/<model>` rather than the upstream's own.";
      };
      websockets = lib.mkOption {
        type = lib.types.bool;
        description = "Whether the gateway serves Responses over a WebSocket.";
      };
      searchRoutes = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        description = ''
          Routes (`owned_by` in /v1/models) whose models search with a hosted
          search tool; null when every model can.
        '';
      };
      relayPort = lib.mkOption {
        type = lib.types.port;
        description = "Loopback port of the gateway's tailnet relay forward.";
      };
    };
  };

  route = lib.types.submodule {
    options = {
      baseUrl = lib.mkOption {
        type = lib.types.str;
        description = "Origin of the gateway's endpoints on this route.";
      };
      catalogUrl = lib.mkOption {
        type = lib.types.str;
        description = "The gateway's catalog on this route.";
      };
      secrets = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Environment variable to the agenix path of its value, besides the gateway's API key.";
      };
      secretHeaders = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "HTTP header to the variable in `secrets` holding its value.";
      };
      relayCheck = lib.mkOption {
        type = lib.types.attrs;
        description = ''
          `listeners`, the relay addresses on this route, and `listenerCheck`,
          the command a client runs on them before it sends credentials
          there; empty on the public route.
        '';
      };
      replacedBaseUrls = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "The other route's origin, which a saved selection may still name.";
      };
    };
  };

  # The access headers' values never reach the store: clients read the
  # variables from the agenix paths at run time.
  publicRoute = gateway: {
    inherit (gateway) baseUrl catalogUrl;
    secrets = {
      CF_ACCESS_CLIENT_ID = access.idPath;
      CF_ACCESS_CLIENT_SECRET = access.secretPath;
    };
    secretHeaders = {
      "CF-Access-Client-Id" = "CF_ACCESS_CLIENT_ID";
      "CF-Access-Client-Secret" = "CF_ACCESS_CLIENT_SECRET";
    };
    relayCheck = { };
    # The relay forward's URL; a home without the relay defines no forward.
    replacedBaseUrls = [ "http://127.0.0.1:${toString gateway.relayPort}" ];
  };

  relayRoute =
    id: gateway:
    let
      forward = relay.forwards.${id};
    in
    {
      baseUrl = forward.url;
      catalogUrl = forward.url + gateway.catalogPath;
      secrets = { };
      secretHeaders = { };
      relayCheck = {
        listeners = [ forward.address ];
        listenerCheck = relay.checker;
      };
      replacedBaseUrls = [ gateway.baseUrl ];
    };
in
{
  options.dotfiles.llmGateways = {
    gateways = lib.mkOption {
      type = lib.types.attrsOf gateway;
      readOnly = true;
      description = "The gateways, keyed by the provider ID each agent registers them under.";
      defaultText = lib.literalMD "CLIProxyAPI and magpie";
      default = {
        cliproxyapi = rec {
          name = "CLIProxyAPI";
          baseUrl = "https://llm.clusters.work";
          tailnetUrl = "https://${flake.lib.tailnetHost "cpa"}";
          apiKeyPath = secretPath "ai-proxy-api-key";
          # `client_version` selects the Codex catalog over OpenAI's list.
          catalogPath = "/v1/models?client_version=${pkgs.llm-agents.codex.version}";
          catalogUrl = baseUrl + catalogPath;
          qualifiedIds = false;
          websockets = true;
          relayPort = 47301;
          # Antigravity drops the hosted search tool, and Chat Completions
          # upstreams turn a Messages search tool into a client function the
          # agent cannot run.
          searchRoutes = [
            "openai"
            "anthropic"
            "xai"
            "meta"
          ];
        };
        magpie = rec {
          name = "magpie";
          baseUrl = "https://magpie.clusters.work";
          tailnetUrl = "https://${flake.lib.tailnetHost "magpie"}";
          apiKeyPath = secretPath "magpie-api-key";
          # /v1/models ignores `client_version` and answers OpenAI's list.
          catalogPath = "/v1/codex/models";
          catalogUrl = baseUrl + catalogPath;
          # Every model is `<magpie provider>/<model>`, such as
          # `claude/claude-opus-5-5`; the part after the slash is the upstream's ID.
          qualifiedIds = true;
          # Responses over a WebSocket is refused with 426.
          websockets = false;
          # A provider that cannot search itself is answered by magpie's own
          # search.
          searchRoutes = null;
          relayPort = 47302;
        };
      };
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      readOnly = true;
      description = "The `age.secrets` every consumer of the gateways declares.";
      default = {
        ai-proxy-api-key.file = ../../../secrets/ai-proxy-api-key.age;
        # A magpie gateway key, made under Gateway → Gateway keys in its web UI.
        magpie-api-key.file = ../../../secrets/magpie-api-key.age;
      };
    };

    relay = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.dotfiles.tailnetRelay.enable;
        defaultText = lib.literalExpression "config.dotfiles.tailnetRelay.enable";
        description = ''
          Whether Claude Code and Codex reach the gateways' tailnet origins
          through this home's tailnet relay instead of their public ones.
          Muse Code and OpenCode stay on the public origins: Muse needs the
          public route's `/muse-code/models` rewrite, and OpenCode's plugin
          does not check who holds the relay's port.
        '';
      };
    };

    routes = lib.mkOption {
      type = lib.types.attrsOf route;
      readOnly = true;
      default = lib.mapAttrs (
        id: gateway: if cfg.relay.enable then relayRoute id gateway else publicRoute gateway
      ) cfg.gateways;
      defaultText = lib.literalMD "the relay route of each gateway where `relay.enable` is set, otherwise its public route";
      description = "How the agents that follow `relay.enable` reach each gateway, keyed like `gateways`.";
    };

    publicRoutes = lib.mkOption {
      type = lib.types.attrsOf route;
      readOnly = true;
      default = lib.mapAttrs (_: publicRoute) cfg.gateways;
      defaultText = lib.literalMD "each gateway's public origin, behind Cloudflare Access";
      description = "The gateways' public routes, for agents that stay on them.";
    };
  };

  config = lib.mkIf cfg.relay.enable {
    dotfiles.tailnetRelay.forwards = lib.mapAttrs (_: gateway: {
      port = gateway.relayPort;
      upstream = gateway.tailnetUrl;
    }) cfg.gateways;
  };
}
