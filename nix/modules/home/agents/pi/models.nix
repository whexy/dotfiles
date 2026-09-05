{
  config,
  pkgs,
  lib,
  apiAccounts,
}:
let
  secretKey = path: "!${pkgs.coreutils}/bin/cat ${path}";
in
{
  providers = {
    openrouter.apiKey = secretKey config.age.secrets.openrouter-api-key.path;
  }
  # Providers billed per API key; only wired when API accounts are enabled.
  // lib.optionalAttrs apiAccounts {
    openai.apiKey = secretKey config.age.secrets.openai-api-key.path;
    anthropic.apiKey = secretKey config.age.secrets.anthropic-api-key.path;
    deepseek.apiKey = secretKey config.age.secrets.deepseek-api-key.path;
  };
}
