# The gateways in the shape model-picker entries take their credentials.
{ config }:
let
  inherit (config.dotfiles.llmGateways) gateways accessToken;
in
{
  inherit gateways accessToken;

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
}
