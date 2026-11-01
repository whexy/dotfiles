# Shared connection facts for the model gateways: CLIProxyAPI and magpie.
#
# Both are published on the public internet behind one Cloudflare Access
# application, so every request needs its service-token headers in addition
# to the gateway's own API key. Each agent loads these from 1Password when it
# starts, with `op-sa read`, and maps them onto the headers with its own
# mechanism.
{ config, codexVersion }:
let
  opSa = "${config.dotfiles.onepassword.package}/bin/op-sa";
  # The command that prints a 1Password secret.
  secretCommand = name: [
    opSa
    "read"
    name
  ];
  # 1Password secret names of the Access service token
  cfAccess = {
    id = "cf-access-dotfiles-id";
    secret = "cf-access-dotfiles-secret";
  };
in
{
  inherit opSa secretCommand cfAccess;

  # env var -> command printing its value, for the launcher wrappers
  cfAccessSecrets = {
    CF_ACCESS_CLIENT_ID = secretCommand cfAccess.id;
    CF_ACCESS_CLIENT_SECRET = secretCommand cfAccess.secret;
  };

  # header -> env var holding its value
  cfAccessHeaderEnv = {
    "CF-Access-Client-Id" = "CF_ACCESS_CLIENT_ID";
    "CF-Access-Client-Secret" = "CF_ACCESS_CLIENT_SECRET";
  };

  # Keyed by the provider ID each agent registers the gateway under. Agents
  # list a gateway's models from its Codex model catalog (`catalogUrl`),
  # whose records carry the display names, limits, and reasoning levels the
  # OpenAI-shaped list omits.
  gateways = {
    cliproxyapi = rec {
      name = "CLIProxyAPI";
      baseUrl = "https://llm.clusters.work";
      apiKeySecret = "ai-proxy-api-key";
      # `client_version` selects the Codex catalog over OpenAI's list.
      catalogUrl = "${baseUrl}/v1/models?client_version=${codexVersion}";
      # Model IDs are the upstream's own.
      qualifiedIds = false;
      websockets = true;
      # Routes (`owned_by` in /v1/models) whose executor passes a hosted search
      # tool to a provider that runs it. Antigravity drops the tool, and Chat
      # Completions upstreams turn a Messages search tool into a client
      # function the agent cannot run.
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
      # Every model searches on Responses and Messages: a provider that cannot
      # search itself is answered by magpie's own search.
      searchRoutes = null;
    };
  };
}
