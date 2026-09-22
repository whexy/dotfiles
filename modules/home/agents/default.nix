# AI coding agents configuration
#
# Tool-specific config lives in each tool's folder, which exports a common
# contract: packages, homeFiles, shellAliases. This module keeps only shared
# concerns: options, the global AGENTS.md, agenix secrets, and merging.
args@{
  pkgs,
  config,
  lib,
  inputs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents;
in
{
  options.dotfiles.agents =
    let
      # Every agent picks the best account tier available on the host:
      # the AI proxy first, then lab-billed API keys, then the
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
      enableProxyAccounts = lib.mkEnableOption "enable models served by the AI proxy";

      firefoxDevtools.enable = lib.mkEnableOption "Mozilla's Firefox DevTools MCP server";

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
      proxy = import ./proxy.nix { inherit config; };
      mcp = import ./mcp.nix { inherit pkgs config lib; };

      # Standalone homes have no `osConfig`; they get no cmux integration.
      cmux = import ./cmux.nix {
        inherit
          pkgs
          config
          lib
          inputs
          ;
        osConfig = args.osConfig or { };
      };

      # Every skill is a directory holding a SKILL.md, per the Agent Skills
      # standard all three harnesses implement.
      skills =
        lib.mapAttrs (name: _: ./skills + "/${name}") (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
        )
        // cmux.skills;
      # Claude Code scans only `~/.claude/skills` and reserves `synced/` there
      # for skills it downloads from the account, so every harness gets one
      # symlink per skill rather than a single directory symlink.
      mkSkillLinks =
        prefix: lib.mapAttrs' (name: src: lib.nameValuePair "${prefix}/${name}" { source = src; }) skills;

      # `~/.agents/skills` used to be one symlink to a store directory; it is
      # now a real directory of per-skill links. Home Manager cannot make that
      # transition on its own: it tries to back the old symlink up by moving
      # its read-only store target, fails, and then refuses to overwrite it,
      # so activation dies before any link is written.
      # Remove once every host has activated a generation that has this.
      migrateSkillsDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        if [ -L "$HOME/.agents/skills" ]; then
          run rm $VERBOSE_ARG "$HOME/.agents/skills"
        fi
      '';
      agents = [
        (import ./pi/home.nix {
          inherit
            pkgs
            config
            lib
            apiAccounts
            proxyAccounts
            proxy
            defaults
            mcp
            ;
        })
        (import ./claude-code/home.nix {
          inherit
            pkgs
            config
            lib
            apiAccounts
            proxyAccounts
            proxy
            withModelPicker
            mcp
            ;
        })
        (import ./codex/home.nix {
          inherit
            pkgs
            config
            lib
            apiAccounts
            proxyAccounts
            proxy
            withModelPicker
            mcp
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
      home = {
        # Single source of truth for global agent rules; every agent reads it.
        # pi gets extra tool-specific guidance appended by its own home.nix.
        file = {
          ".codex/AGENTS.md".source = ./AGENTS.md;
          ".claude/CLAUDE.md".source = ./AGENTS.md;
        }
        # User-scope skill location for both pi and codex; adding a skill is
        # a new directory under ./skills, never a change here.
        // mkSkillLinks ".agents/skills"
        // mkSkillLinks ".claude/skills"
        // lib.mergeAttrsList (map (a: a.homeFiles or { }) agents);

        packages = lib.concatMap (a: a.packages or [ ]) agents;

        shellAliases = lib.mergeAttrsList (map (a: a.shellAliases or { }) agents);

        activation = cmux.activation // {
          inherit migrateSkillsDir;
        };
      };

      # Secrets stay at agenix's default runtime location. Every consumer
      # reads `config.age.secrets.*.path` through a shell, which is what
      # expands the `${XDG_RUNTIME_DIR}` / `$(getconf ...)` fragment agenix
      # generates, so no agent needs a hardcoded path.
      age.secrets = {
        openrouter-api-key.file = ../../../secrets/openrouter-api-key.age;
      }
      // lib.optionalAttrs cfg.enableApiAccounts {
        openai-api-key.file = ../../../secrets/openai-api-key.age;
        anthropic-api-key.file = ../../../secrets/anthropic-api-key.age;
        deepseek-api-key.file = ../../../secrets/deepseek-api-key.age;
      }
      // lib.optionalAttrs cfg.enableProxyAccounts {
        ai-proxy-api-key.file = ../../../secrets/ai-proxy-api-key.age;
        # The proxy is reachable from the public internet through
        # Cloudflare Access; every agent must present the service token.
        cf-access-dotfiles-id.file = ../../../secrets/cf-access-dotfiles-id.age;
        cf-access-dotfiles-secret.file = ../../../secrets/cf-access-dotfiles-secret.age;
      };
    }
  );
}
