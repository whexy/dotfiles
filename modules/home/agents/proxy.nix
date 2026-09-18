# Shared connection facts for the AI proxy.
#
# The proxy is published on the public internet and gated by Cloudflare
# Access, so every request needs the service-token headers in addition to
# the proxy's own API key. Agents cannot read agenix files themselves, so
# each one is handed the secret paths and maps them onto the headers with
# its own mechanism.
{ config }:
let
  secretPath = name: config.age.secrets.${name}.path;
in
{
  baseUrl = "https://llm.clusters.work";

  apiKeyPath = secretPath "ai-proxy-api-key";
  cfAccessIdPath = secretPath "cf-access-dotfiles-id";
  cfAccessSecretPath = secretPath "cf-access-dotfiles-secret";

  # env var -> agenix secret file, for the launcher wrappers
  cfAccessSecrets = {
    CF_ACCESS_CLIENT_ID = secretPath "cf-access-dotfiles-id";
    CF_ACCESS_CLIENT_SECRET = secretPath "cf-access-dotfiles-secret";
  };

  # header -> env var holding its value
  cfAccessHeaderEnv = {
    "CF-Access-Client-Id" = "CF_ACCESS_CLIENT_ID";
    "CF-Access-Client-Secret" = "CF_ACCESS_CLIENT_SECRET";
  };
}
