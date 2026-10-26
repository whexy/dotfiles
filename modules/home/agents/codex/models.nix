{ proxy }:
# Codex discovers a gateway's models itself through `model_catalog_url`, so
# its own model picker lists them; each gateway's entry only configures the
# provider. The native login entry clears the provider so Codex uses its saved
# ChatGPT login. It stays after the CLIProxyAPI entry, which removed
# selections migrate to.
let
  # The gateways sit behind Cloudflare Access. `env_http_headers` maps a
  # header onto the env var holding its value, so the picker exports the
  # service token and codex reads it at request time, for the catalog too.
  gatewayEntry =
    id: extra:
    let
      gateway = proxy.gateways.${id};
    in
    {
      label = "${id} (default models)";
      secrets = proxy.cfAccessSecrets // {
        OPENAI_API_KEY = gateway.apiKeyPath;
      };
      settings = {
        model_provider = id;
        features.api_key_model_discovery = true;
        model_providers.${id} = {
          inherit (gateway) name;
          base_url = "${gateway.baseUrl}/v1";
          model_catalog_url = gateway.catalogUrl;
          wire_api = "responses";
          supports_websockets = gateway.websockets;
          requires_openai_auth = false;
          env_key = "OPENAI_API_KEY";
          env_http_headers = proxy.cfAccessHeaderEnv;
        }
        // extra.provider or { };
      }
      // extra.settings or { };
    };
in
[
  (gatewayEntry "cliproxyapi" { })
  (gatewayEntry "magpie" {
    # Without a model Codex starts on the catalog's first, and magpie ranks
    # its routing groups first.
    settings.model = "codex/gpt-6.1-sol";
    # Codex offers its image tool and web.run search only to a provider
    # carrying this header, as magpie's own Codex config does.
    provider.http_headers."x-openai-actor-authorization" = "magpie";
  })
  { label = "default (ChatGPT login)"; }
]
