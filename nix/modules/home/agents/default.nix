# AI coding agents configuration
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
      opencode_settings = import ./opencode/config.nix {
        inherit
          config
          lib
          apiAccounts
          proxyAccounts
          ;
      };
      opencode_tui = import ./opencode/tui.nix;
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
          ;
      };
      pi_web_search = import ./pi/web-search.nix { inherit proxyAccounts; };
      withModelPicker = import ./withModelPicker.nix { inherit pkgs lib; };
      # Stamp the configured model into gcai via GCAI_MODEL.
      gcai = pkgs.writeShellScriptBin "gcai" ''
        export GCAI_MODEL=${lib.escapeShellArg cfg.gcai.model}
        exec ${perSystem.self.gcai}/bin/gcai "$@"
      '';
      claude = withModelPicker {
        name = "claude";
        package = pkgs.llm-agents.claude-code;
        entries = import ./claude-code/models.nix {
          inherit
            config
            lib
            apiAccounts
            proxyAccounts
            ;
        };
      };
      codex = withModelPicker {
        name = "codex";
        package = pkgs.llm-agents.codex;
        entries = import ./codex/models.nix {
          inherit
            config
            lib
            apiAccounts
            proxyAccounts
            ;
        };
      };
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
        file = {
          # Single source of truth for global agent rules; every agent reads it.
          ".pi/agent/AGENTS.md".source = ./AGENTS.md;
          ".config/opencode/AGENTS.md".source = ./AGENTS.md;
          ".codex/AGENTS.md".source = ./AGENTS.md;
          ".claude/CLAUDE.md".source = ./AGENTS.md;
          # Deploy the notification plugin so it is auto-loaded by OpenCode.
          ".config/opencode/plugins/notify.js".source = ./opencode/plugins/notify.js;
          ".pi/agent/settings.json".text = builtins.toJSON pi_settings;
          ".pi/agent/models.json".text = builtins.toJSON pi_models;
          ".pi/web-search.json".text = builtins.toJSON pi_web_search;
          ".claude/settings.json".source = ./claude-code/settings.json;
        }
        // lib.optionalAttrs proxyAccounts {
          # Discover the proxy catalog and clone matching model metadata from pi.
          ".pi/agent/extensions/ai-proxy.ts".source = ./pi/ai-proxy.ts;
        };

        packages = [
          pkgs.llm-agents.pi
          claude
          codex
          gcai
        ]
        ++ lib.optionals proxyAccounts [ perSystem.self.ai-quota ];

        shellAliases = {
          oc = "opencode";
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
        # Management key for the CLIProxyAPI /v0/management endpoints,
        # consumed by the ai-quota package.
        ai-proxy-mgmt-key = {
          file = ../../../../secrets/ai-proxy-mgmt-key.age;
          path = "${config.home.homeDirectory}/.secrets/ai-proxy-mgmt-key";
        };
      };

      programs = {
        opencode = {
          enable = true;
          package = pkgs.llm-agents.opencode;
          settings = opencode_settings;
          tui = opencode_tui;
        };
      };
    }
  );
}
