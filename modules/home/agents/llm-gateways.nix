# The model gateways agents reach: CLIProxyAPI and magpie.
#
# Both are published on the public internet behind one Cloudflare Access
# application, so every request needs its service-token headers in addition
# to the gateway's own API key. Each consumer loads both from 1Password when
# it starts, with `op-sa read`, and sends them its own way.
{ lib, pkgs, ... }:
let
  gateway = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name.";
      };
      baseUrl = lib.mkOption {
        type = lib.types.str;
        description = "Origin of the gateway's OpenAI- and Anthropic-compatible endpoints.";
      };
      apiKeySecret = lib.mkOption {
        type = lib.types.str;
        description = "1Password secret name of the gateway's API key.";
      };
      catalogUrl = lib.mkOption {
        type = lib.types.str;
        description = ''
          The gateway's Codex model catalog, whose records carry the display
          names, limits, and reasoning levels the OpenAI-shaped list omits.
          Agents list the gateway's models from it.
        '';
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
    };
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
          apiKeySecret = "ai-proxy-api-key";
          # `client_version` selects the Codex catalog over OpenAI's list.
          catalogUrl = "${baseUrl}/v1/models?client_version=${pkgs.llm-agents.codex.version}";
          qualifiedIds = false;
          websockets = true;
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
          apiKeySecret = "magpie-api-key";
          # /v1/models ignores `client_version` and answers OpenAI's list.
          catalogUrl = "${baseUrl}/v1/codex/models";
          # Every model is `<magpie provider>/<model>`, such as
          # `claude/claude-opus-5-5`; the part after the slash is the upstream's ID.
          qualifiedIds = true;
          # Responses over a WebSocket is refused with 426.
          websockets = false;
          # A provider that cannot search itself is answered by magpie's own
          # search.
          searchRoutes = null;
        };
      };
    };

    accessToken = lib.mkOption {
      type = lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "1Password secret name of the service token's client ID.";
          };
          secret = lib.mkOption {
            type = lib.types.str;
            description = "1Password secret name of the service token's client secret.";
          };
        };
      };
      readOnly = true;
      default = {
        id = "cf-access-dotfiles-id";
        secret = "cf-access-dotfiles-secret";
      };
      description = "The Cloudflare Access service token in front of every gateway.";
    };
  };
}
