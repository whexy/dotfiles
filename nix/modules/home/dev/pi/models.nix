{
  config,
  pkgs,
  lib,
}:
let
  inherit (config.dotfiles) tailscale;
  secretKey = path: "!${pkgs.coreutils}/bin/cat ${path}";
in
{
  providers = {
    openai.apiKey = secretKey config.age.secrets.openai-api-key.path;
    anthropic.apiKey = secretKey config.age.secrets.anthropic-api-key.path;
    deepseek.apiKey = secretKey config.age.secrets.deepseek-api-key.path;
  }
  # The AI proxy lives on the tailnet; only reachable with Tailscale.
  // lib.optionalAttrs tailscale {
    moonshotai = {
      baseUrl = "https://ai-proxy.at-basking.ts.net/v1";
      apiKey = "kfc-vivo-50";
    };
  };
}
