# The gateways in the shape model-picker entries take their credentials.
{ config }:
let
  inherit (config.dotfiles.llmGateways) gateways accessToken;
  opSa = "${config.dotfiles.onepassword.package}/bin/op-sa";
  # The command that prints a 1Password secret.
  secretCommand = name: [
    opSa
    "read"
    name
  ];
in
{
  inherit
    gateways
    accessToken
    opSa
    secretCommand
    ;

  # env var -> command printing its value, for the launcher wrappers
  accessSecrets = {
    CF_ACCESS_CLIENT_ID = secretCommand accessToken.id;
    CF_ACCESS_CLIENT_SECRET = secretCommand accessToken.secret;
  };

  # header -> env var holding its value
  accessHeaderEnv = {
    "CF-Access-Client-Id" = "CF_ACCESS_CLIENT_ID";
    "CF-Access-Client-Secret" = "CF_ACCESS_CLIENT_SECRET";
  };
}
