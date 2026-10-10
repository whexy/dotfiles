# AI coding agents configuration
#
# Tool-specific config lives in each tool's folder, which exports a common
# contract: packages, homeFiles, shellAliases, activation, and the
# systemdUserServices/launchdAgents it runs. This module keeps only shared
# concerns: options, the global AGENTS.md, agenix secrets, and merging.
args@{
  pkgs,
  config,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents;
in
{
  options.dotfiles.agents = {
    enable = lib.mkEnableOption "agents";

    firefoxDevtools.enable = lib.mkEnableOption "Mozilla's Firefox DevTools MCP server";

    t3code = {
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "T3 Code package; null selects the pinned nightly package.";
      };
      server.enable = lib.mkOption {
        type = lib.types.bool;
        # Clients only reach the server through Tailscale Serve. Standalone
        # homes have no osConfig to say whether this machine is on the tailnet.
        default = args.osConfig.dotfiles.network.tailscale.enable or false;
        defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false";
        description = "Whether to run the T3 Code server, published on the tailnet through Tailscale Serve.";
      };
      pair.enable = lib.mkEnableOption "the t3-pair helper, which mints pairing URLs for T3 Code servers";
    };

    defaultProvider = lib.mkOption {
      type = lib.types.enum [ "cliproxyapi" ];
      default = "cliproxyapi";
      description = "Provider serving the default model.";
    };
    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "claude-opus-5-5";
      description = "Model agents use unless told otherwise.";
    };

    defaultCheapProvider = lib.mkOption {
      type = lib.types.enum [ "cliproxyapi" ];
      default = "cliproxyapi";
      description = "Provider serving the cheap model.";
    };
    defaultCheapModel = lib.mkOption {
      type = lib.types.str;
      default = "claude-sonnet-5-5";
      description = "Model for bulk or low-stakes work.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
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
      withModelPicker = import ./withModelPicker.nix {
        inherit pkgs;
        agentSettings = perSystem.self.agent-settings;
      };
      proxy = import ./proxy.nix { inherit config; };
      mcp = import ./mcp.nix { inherit pkgs config lib; };
      # Agents commit as the user but did not write the code, so they leave
      # commits and tags unsigned while the user's own git keeps signing. The
      # include must come first: a later value wins.
      gitConfig = pkgs.writeText "agent-gitconfig" ''
        [include]
          path = ${config.xdg.configHome}/git/config
        [commit]
          gpgSign = false
        [tag]
          gpgSign = false
      '';
      # Shell lines every agent launcher runs before starting its agent; the
      # agent's tool shells inherit what they export.
      prelude = mcp.exportSecrets + ''
        export GIT_CONFIG_GLOBAL=${gitConfig}
      '';
      # Every skill is a directory holding a SKILL.md, per the Agent Skills
      # standard every harness implements.
      skills = lib.mapAttrs (name: _: ./skills + "/${name}") (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
      );
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
      # cmux wrote this pi extension outside Home Manager, so nothing else
      # removes it now that cmux is gone; the marker keeps a hand-written file
      # of the same name safe. Remove once every macOS host has activated this.
      removeCmuxPiExtension = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        extension="$HOME/.pi/agent/extensions/cmux-session.ts"
        if [ -f "$extension" ] && grep -q cmux-pi-session-extension-marker "$extension"; then
          run rm $VERBOSE_ARG "$extension"
        fi
      '';
      agents = [
        (import ./pi/home.nix {
          inherit
            pkgs
            lib
            proxy
            defaults
            mcp
            prelude
            ;
        })
        (import ./opencode/home.nix {
          inherit
            pkgs
            lib
            proxy
            defaults
            mcp
            prelude
            ;
        })
        (import ./claude-code/home.nix {
          inherit
            pkgs
            lib
            proxy
            withModelPicker
            mcp
            prelude
            ;
        })
        (import ./codex/home.nix {
          inherit
            pkgs
            lib
            proxy
            withModelPicker
            mcp
            prelude
            ;
        })
        (import ./t3code/home.nix {
          inherit
            pkgs
            config
            lib
            perSystem
            gitConfig
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
        # pi and Claude Code get extra tool-specific guidance appended by
        # their own home.nix.
        file = {
          ".codex/AGENTS.md".source = ./AGENTS.md;
          ".config/opencode/AGENTS.md".source = ./AGENTS.md;
        }
        # User-scope skill location for pi, codex, and opencode; adding a skill is
        # a new directory under ./skills, never a change here.
        // mkSkillLinks ".agents/skills"
        // mkSkillLinks ".claude/skills"
        // lib.mergeAttrsList (map (a: a.homeFiles or { }) agents);

        # CLIs that shared skills drive; every harness reaches them through PATH.
        packages = [ perSystem.self.wechat-cli ] ++ lib.concatMap (a: a.packages or [ ]) agents;

        shellAliases = lib.mergeAttrsList (map (a: a.shellAliases or { }) agents);

        activation = lib.mergeAttrsList (map (a: a.activation or { }) agents) // {
          inherit migrateSkillsDir removeCmuxPiExtension;
        };
      };

      systemd.user.services = lib.mergeAttrsList (map (a: a.systemdUserServices or { }) agents);
      launchd.agents = lib.mergeAttrsList (map (a: a.launchdAgents or { }) agents);

      # Secrets stay at agenix's default runtime location. Every consumer
      # reads `config.age.secrets.*.path` through a shell, which is what
      # expands the `${XDG_RUNTIME_DIR}` / `$(getconf ...)` fragment agenix
      # generates, so no agent needs a hardcoded path.
      age.secrets = {
        ai-proxy-api-key.file = ../../../secrets/ai-proxy-api-key.age;
        # The proxy is reachable from the public internet through
        # Cloudflare Access; every agent must present the service token.
        cf-access-dotfiles-id.file = ../../../secrets/cf-access-dotfiles-id.age;
        cf-access-dotfiles-secret.file = ../../../secrets/cf-access-dotfiles-secret.age;
        # Bearer token for the `personal` MCP server (see mcp.nix).
        n8n-mcp-token.file = ../../../secrets/n8n-mcp-token.age;
      };
    }
  );
}
