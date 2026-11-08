# The gateways in the shape model-picker entries take their credentials.
{ config }:
let
  inherit (config.dotfiles.llmGateways) gateways accessToken relay;

  # env var -> agenix path of its value, for the launcher wrappers
  accessSecrets = {
    CF_ACCESS_CLIENT_ID = accessToken.idPath;
    CF_ACCESS_CLIENT_SECRET = accessToken.secretPath;
  };

  # header -> env var holding its value
  accessHeaderEnv = {
    "CF-Access-Client-Id" = "CF_ACCESS_CLIENT_ID";
    "CF-Access-Client-Secret" = "CF_ACCESS_CLIENT_SECRET";
  };

  relayUrl = id: "http://127.0.0.1:${toString relay.ports.${id}}";
in
{
  inherit
    gateways
    accessToken
    accessSecrets
    accessHeaderEnv
    ;

  # How the agents agent-settings launches reach gateway `id`: through the
  # tailnet relay where this home runs one, otherwise at the public origin
  # behind Cloudflare Access. `listenerCheck` runs on the relay ports
  # (`listeners`) before agent-settings sends credentials there, and
  # `replacedBaseUrls` is the other route's origin, which a saved selection
  # may still name.
  endpoint =
    id:
    let
      gateway = gateways.${id};
    in
    if relay.enable then
      {
        baseUrl = relayUrl id;
        catalogUrl = relayUrl id + gateway.catalogPath;
        secrets = { };
        secretHeaders = { };
        relayCheck = {
          listeners = [ config.dotfiles.tailnetRelay.forwards.${id}.address ];
          listenerCheck = config.dotfiles.tailnetRelay.checker;
        };
        replacedBaseUrls = [ gateway.baseUrl ];
      }
    else
      {
        inherit (gateway) baseUrl catalogUrl;
        secrets = accessSecrets;
        secretHeaders = accessHeaderEnv;
        relayCheck = { };
        replacedBaseUrls = [ (relayUrl id) ];
      };
}
