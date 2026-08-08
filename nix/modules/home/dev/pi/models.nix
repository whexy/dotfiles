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
    # OpenCode Go subscription. deepseek-v4-flash and grok-4.5 are in pi's
    # bundled catalog; the two newer models below are merged into it.
    # Full list: https://opencode.ai/zen/go/v1/models
    opencode-go = {
      apiKey = secretKey config.age.secrets.opencode-api-key.path;
      # Bundled catalog lists grok-4.5 cached reads at $0.50; actual Go price is $0.30.
      modelOverrides."grok-4.5".cost = {
        input = 2;
        output = 6;
        cacheRead = 0.3;
        cacheWrite = 0;
      };
      models = [
        {
          id = "gpt-5.6-luna";
          name = "GPT 5.6 Luna";
          api = "openai-responses";
          baseUrl = "https://opencode.ai/zen/go/v1";
          reasoning = true;
          input = [
            "text"
            "image"
          ];
          contextWindow = 400000;
          maxTokens = 128000;
          cost = {
            input = 0.2;
            output = 1.2;
            cacheRead = 0.02;
            cacheWrite = 0.25;
            tiers = [
              {
                inputTokensAbove = 272000;
                input = 0.4;
                output = 1.8;
                cacheRead = 0.04;
                cacheWrite = 0.5;
              }
            ];
          };
        }
        {
          id = "qwen3.8-max";
          name = "Qwen3.8 Max";
          api = "anthropic-messages";
          baseUrl = "https://opencode.ai/zen/go";
          reasoning = true;
          input = [ "text" ];
          contextWindow = 1000000;
          maxTokens = 65536;
          cost = {
            input = 2;
            output = 6;
            cacheRead = 0.25;
            cacheWrite = 2.5;
          };
        }
      ];
    };
  }
  # The AI proxy lives on the tailnet; only reachable with Tailscale.
  // lib.optionalAttrs tailscale {
    moonshotai = {
      baseUrl = "https://ai-proxy.at-basking.ts.net/v1";
      apiKey = "kfc-vivo-50";
    };
  };
}
