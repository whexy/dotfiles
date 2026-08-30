# AI coding agents configuration
#
# Tool-specific config lives in each tool's folder, which exports a common
# contract: packages, homeFiles, shellAliases. This module keeps only shared
# concerns: options, the global AGENTS.md, agenix secrets, and merging.
args@{
  pkgs,
  config,
  lib,
  perSystem,
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

    gcai.model = lib.mkOption {
      type = lib.types.str;
      default =
        if cfg.enableProxyAccounts then "ai-proxy/gpt-5.6-luna" else "opencode-go/deepseek-v4-flash";
      defaultText = lib.literalExpression ''
        if config.dotfiles.agents.enableProxyAccounts
        then "ai-proxy/gpt-5.6-luna"
        else "opencode-go/deepseek-v4-flash"
      '';
      description = "provider/model gcai uses to generate commit messages with pi";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      apiAccounts = cfg.enableApiAccounts;
      proxyAccounts = cfg.enableProxyAccounts;
      withModelPicker = import ./withModelPicker.nix { inherit pkgs lib; };
      opencode = import ./opencode/home.nix {
        inherit
          pkgs
          config
          lib
          apiAccounts
          proxyAccounts
          ;
      };
      agents = [
        opencode
        (import ./pi/home.nix {
          inherit
            pkgs
            config
            lib
            apiAccounts
            proxyAccounts
            ;
        })
        (import ./claude-code/home.nix {
          inherit
            pkgs
            config
            lib
            apiAccounts
            proxyAccounts
            withModelPicker
            ;
        })
        (import ./codex/home.nix {
          inherit
            pkgs
            config
            lib
            apiAccounts
            proxyAccounts
            withModelPicker
            ;
        })
        (import ./gcai/home.nix {
          inherit
            pkgs
            lib
            perSystem
            ;
          model = cfg.gcai.model;
        })
      ];
    in
    {
      # The AI proxy lives on the tailnet; integrated hosts must run
      # Tailscale. Standalone homes manage connectivity themselves.
      assertions = [
        {
          assertion =
            !cfg.enableProxyAccounts || (osConfig == null || osConfig.dotfiles.network.tailscale.enable);
          message = "dotfiles.agents.enableProxyAccounts requires dotfiles.network.tailscale.enable";
        }
      ];

      home = {
        # Single source of truth for global agent rules; every agent reads it.
        file = {
          ".pi/agent/AGENTS.md".source = ./AGENTS.md;
          ".config/opencode/AGENTS.md".source = ./AGENTS.md;
          ".codex/AGENTS.md".source = ./AGENTS.md;
          ".claude/CLAUDE.md".source = ./AGENTS.md;
        }
        // lib.mergeAttrsList (map (a: a.homeFiles or { }) agents);

        packages = lib.concatMap (a: a.packages or [ ]) agents;

        shellAliases = lib.mergeAttrsList (map (a: a.shellAliases or { }) agents);
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
        openrouter-api-key = {
          file = ../../../../secrets/openrouter-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/openrouter-api-key";
        };
      }
      // lib.optionalAttrs cfg.enableProxyAccounts {
        ai-proxy-api-key = {
          file = ../../../../secrets/ai-proxy-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/ai-proxy-api-key";
        };
      };

      programs = {
        opencode = {
          enable = true;
          inherit (opencode) package settings tui;
        };
      };
    }
  );
}
