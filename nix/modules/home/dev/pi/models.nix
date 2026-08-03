{ config, pkgs }:
let
  secretKey = path: "!${pkgs.coreutils}/bin/cat ${path}";
in
{
  providers = {
    # Built-in moonshotai provider routed through the AI proxy. kimi-k3 ships
    # with pi, including Kimi-specific compat (deferredToolsMode, thinkingLevelMap).
    moonshotai = {
      baseUrl = "https://ai-proxy.at-basking.ts.net/v1";
      apiKey = "kfc-vivo-50";
    };

    openai.apiKey = secretKey config.age.secrets.openai-api-key.path;
    anthropic.apiKey = secretKey config.age.secrets.anthropic-api-key.path;
    deepseek.apiKey = secretKey config.age.secrets.deepseek-api-key.path;
  };
}
