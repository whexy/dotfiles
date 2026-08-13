# AI coding agents configuration
args@{
  pkgs,
  config,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.agents;
in
{
  options.dotfiles.agents = {
    enable = lib.mkEnableOption "agents";
    enableApiAccounts = lib.mkEnableOption "enable models billed by API";
    enableProxyAccounts = lib.mkEnableOption "enable models served by the tailnet AI proxy";
  };

  config = lib.mkIf cfg.enable (
    let
      apiAccounts = cfg.enableApiAccounts;
      proxyAccounts = cfg.enableProxyAccounts;
      opencode2_settings = import ./opencode2/config.nix {
        inherit
          config
          lib
          apiAccounts
          proxyAccounts
          ;
      };
      opencode2_cli = import ./opencode2/cli.nix;
      pi_settings = import ./pi/settings.nix {
        inherit
          pkgs
          lib
          apiAccounts
          proxyAccounts
          ;
      };
      pi_models = import ./pi/models.nix {
        inherit
          config
          pkgs
          lib
          apiAccounts
          proxyAccounts
          ;
      };
      pi_web_search = import ./pi/web-search.nix;
    in
    {
      # The AI proxy lives on the tailnet; it is unreachable without Tailscale.
      assertions = [
        {
          assertion =
            !cfg.enableProxyAccounts || (osConfig != null && osConfig.dotfiles.network.tailscale.enable);
          message = "dotfiles.agents.enableProxyAccounts requires dotfiles.network.tailscale.enable";
        }
      ];

      home = {
        file = {
          ".config/opencode/opencode.json".text = builtins.toJSON opencode2_settings;
          ".config/opencode/cli.json".text = builtins.toJSON opencode2_cli;
          ".pi/agent/settings.json".text = builtins.toJSON pi_settings;
          ".pi/agent/models.json".text = builtins.toJSON pi_models;
          ".pi/web-search.json".text = builtins.toJSON pi_web_search;
        };

        packages = [
          pkgs.llm-agents.pi
          pkgs.llm-agents.opencode2
        ];

        shellAliases = {
          oc2 = "opencode2";
        };
      };

      age.secrets = {
        opencode-api-key = {
          file = ../../../../secrets/opencode-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/opencode-api-key";
        };
      }
      // lib.optionalAttrs cfg.enableApiAccounts {
        openai-api-key = {
          file = ../../../../secrets/openai-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/openai-api-key";
        };
        anthropic-api-key = {
          file = ../../../../secrets/anthropic-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/anthropic-api-key";
        };
        deepseek-api-key = {
          file = ../../../../secrets/deepseek-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/deepseek-api-key";
        };
      }
      // lib.optionalAttrs cfg.enableProxyAccounts {
        ai-proxy-api-key = {
          file = ../../../../secrets/ai-proxy-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/ai-proxy-api-key";
        };
      };
    }
  );
}
