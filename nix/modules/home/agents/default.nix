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
  options.dotfiles.agents =
    let
      # Every agent picks the best account tier available on the host:
      # the tailnet proxy first, then lab-billed API keys, then the
      # always-present OpenRouter key.
      byTier =
        {
          proxy,
          api,
          fallback,
        }:
        if cfg.enableProxyAccounts then
          proxy
        else if cfg.enableApiAccounts then
          api
        else
          fallback;
      mkModelOption =
        description: tiers:
        lib.mkOption {
          type = lib.types.str;
          default = byTier tiers;
          defaultText = lib.literalExpression ''
            if config.dotfiles.agents.enableProxyAccounts then "${tiers.proxy}"
            else if config.dotfiles.agents.enableApiAccounts then "${tiers.api}"
            else "${tiers.fallback}"
          '';
          inherit description;
        };
    in
    {
      enable = lib.mkEnableOption "agents";
      enableApiAccounts = lib.mkEnableOption "enable models billed by API";
      enableProxyAccounts = lib.mkEnableOption "enable models served by the tailnet AI proxy";

      defaultProvider = mkModelOption "provider serving the default model" {
        proxy = "ai-proxy";
        api = "openai";
        fallback = "openrouter";
      };
      defaultModel = mkModelOption "model agents use unless told otherwise" {
        proxy = "claude-opus-5";
        api = "gpt-5.6-sol";
        fallback = "z-ai/glm-5.3-flash";
      };

      defaultCheapProvider = mkModelOption "provider serving the cheap model" {
        proxy = "ai-proxy";
        api = "openai";
        fallback = "openrouter";
      };
      defaultCheapModel = mkModelOption "model for bulk or low-stakes work" {
        proxy = "claude-sonnet-5";
        api = "gpt-5.6-luna";
        fallback = "meta/muse-spark-1.3-contributor";
      };
    };

  config = lib.mkIf cfg.enable (
    let
      apiAccounts = cfg.enableApiAccounts;
      proxyAccounts = cfg.enableProxyAccounts;
      defaults = {
        inherit (cfg)
          defaultProvider
          defaultModel
          defaultCheapProvider
          defaultCheapModel
          ;
        default = "${cfg.defaultProvider}/${cfg.defaultModel}";
        cheap = "${cfg.defaultCheapProvider}/${cfg.defaultCheapModel}";
      };
      withModelPicker = import ./withModelPicker.nix { inherit pkgs lib; };
      agents = [
        (import ./pi/home.nix {
          inherit
            pkgs
            config
            lib
            apiAccounts
            proxyAccounts
            defaults
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
            defaults
            ;
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
        # pi gets extra tool-specific guidance appended by its own home.nix.
        file = {
          ".codex/AGENTS.md".source = ./AGENTS.md;
          ".claude/CLAUDE.md".source = ./AGENTS.md;
        }
        // lib.mergeAttrsList (map (a: a.homeFiles or { }) agents);

        packages = lib.concatMap (a: a.packages or [ ]) agents;

        shellAliases = lib.mergeAttrsList (map (a: a.shellAliases or { }) agents);
      };

      age.secrets = {
        openrouter-api-key = {
          file = ../../../../secrets/openrouter-api-key.age;
          path = "${config.home.homeDirectory}/.secrets/openrouter-api-key";
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
