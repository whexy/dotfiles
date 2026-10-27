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
  flake,
  ...
}:
let
  cfg = config.dotfiles.agents;
  # Every agent is configured for both gateways; these pick the defaults.
  gatewayType = lib.types.enum [
    "cliproxyapi"
    "magpie"
  ];
  # magpie serves the Claude subscription as its `claude` provider.
  claudeModel = gateway: model: if gateway == "magpie" then "claude/${model}" else model;
in
{
  options.dotfiles.agents = {
    enable = lib.mkEnableOption "agents";

    firefoxDevtools.enable = lib.mkEnableOption "Mozilla's Firefox DevTools MCP server";

    iphoneUse.enable = lib.mkEnableOption "the iPhone Use MCP server, which drives a USB-connected iPhone through WebDriverAgent";

    tldraw.enable = lib.mkOption {
      type = lib.types.bool;
      # The server only resolves on the tailnet, so registering it elsewhere
      # leaves every agent with a permanently failing MCP server. Standalone
      # homes have no osConfig to say whether this machine is on the tailnet.
      default = args.osConfig.dotfiles.network.tailscale.enable or false;
      defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false";
      description = "Whether to register the tailnet tldraw MCP server (draw.at-basking.ts.net).";
    };

    rea = {
      enable = lib.mkEnableOption "the REA reverse-engineering MCP server and CLI, with Ghidra";
      browser.enable = lib.mkEnableOption "website analysis and module-import tracing through Chromium";
      android.enable = lib.mkEnableOption "APK decompilation (JADX), resource decoding (Apktool), and adb device tools";
      binary.enable = lib.mkEnableOption "offline ELF layout and recorded-crash tools (pwntools, pwndbg; Linux x64)";
      firmware.enable = lib.mkEnableOption "firmware scanning and extraction (Binwalk, Unblob; Linux)";
      javascript.enable = lib.mkEnableOption "JavaScript source recovery from bundles (Wakaru; Linux)";
      networkCapture.enable = lib.mkEnableOption "native mitmproxy capture decoding (mitmdump; Linux)";
      dotnet.enable = lib.mkEnableOption "ILSpy decompilation of .NET assemblies";
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          REA_JEB_MCP_URL = "http://127.0.0.1:8425/mcp";
        };
        description = ''
          Further `REA_*` settings for engines that cannot come from nixpkgs,
          such as a licensed JEB or IDA install.
        '';
      };
    };

    video.enable = lib.mkEnableOption "the video-editing toolkit, driving DaVinci Resolve Studio on macOS or from WSL";

    studio.enable = lib.mkOption {
      type = lib.types.bool;
      # B-roll slots take generated footage from it.
      default = cfg.video.enable;
      defaultText = lib.literalExpression "config.dotfiles.agents.video.enable";
      description = ''
        Whether to register SimpleStudio's MCP server, which generates video
        on the studio's GPU Workers. Each agent signs in to it once per
        machine, through Cloudflare Access.
      '';
    };

    spark = {
      enable = lib.mkEnableOption "the Spark skill, which searches and reads mail through the `spark` CLI that Spark Desktop installs";
      server = {
        enable = lib.mkEnableOption ''
          spark-mcp, which serves Spark Desktop's email-reading tools to MCP
          clients off this Mac. A Cloudflare tunnel publishes it at
          `https://<host>-spark.clusters.work/mcp` (`flake.lib.publicHost`),
          behind a Cloudflare Access application that admits clients by
          OAuth or service token
        '';
        accessAud = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            AUD tag of the Cloudflare Access application covering this host's
            spark-mcp hostname. The server admits only requests carrying an
            Access assertion for it. The tag identifies the application; it
            is not a secret.
          '';
        };
      };
    };

    t3code = {
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "T3 Code package; null selects the pinned nightly package.";
      };
      server = {
        enable = lib.mkOption {
          type = lib.types.bool;
          # Standalone homes have no osConfig to say whether this machine is
          # on the tailnet, so they enable the server themselves.
          default = args.osConfig.dotfiles.network.tailscale.enable or false;
          defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false";
          description = ''
            Whether to run the T3 Code server. It listens on loopback only,
            for Tailscale Serve and the Cloudflare tunnel to publish.
          '';
        };
        tailnet.enable = lib.mkOption {
          type = lib.types.bool;
          default = args.osConfig.dotfiles.network.tailscale.enable or false;
          defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false";
          description = ''
            Whether to publish the server on the tailnet through Tailscale
            Serve at `https://<MagicDNS name>:35338`.
          '';
        };
        tunnel = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = cfg.t3code.server.enable;
            defaultText = lib.literalExpression "config.dotfiles.agents.t3code.server.enable";
            description = ''
              Whether to publish the server on the public internet through a
              Cloudflare tunnel at the host's `flake.lib.publicHost "t3"` name. The
              host creates its own tunnel and DNS record on first start with the
              shared `cloudflared-cert` secret. The server's own pairing is the
              only gate in front of it.
            '';
          };
          hostName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = args.osConfig.dotfiles.host.hostName or null;
            defaultText = lib.literalExpression "osConfig.dotfiles.host.hostName or null";
            description = ''
              Dotfiles host name the tunnel and its public name derive from.
              Standalone homes have no osConfig to supply it.
            '';
          };
        };
      };
      pair.enable = lib.mkEnableOption "the t3-pair helper, which mints pairing URLs for T3 Code servers";
    };

    defaultProvider = lib.mkOption {
      type = gatewayType;
      default = "cliproxyapi";
      description = "Gateway serving the default model.";
    };
    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = claudeModel cfg.defaultProvider "claude-opus-5-5";
      defaultText = lib.literalExpression ''if defaultProvider == "magpie" then "claude/claude-opus-5-5" else "claude-opus-5-5"'';
      description = "Model agents use unless told otherwise.";
    };

    defaultCheapProvider = lib.mkOption {
      type = gatewayType;
      default = "cliproxyapi";
      description = "Gateway serving the cheap model.";
    };
    defaultCheapModel = lib.mkOption {
      type = lib.types.str;
      default = claudeModel cfg.defaultCheapProvider "claude-sonnet-5-5";
      defaultText = lib.literalExpression ''if defaultCheapProvider == "magpie" then "claude/claude-sonnet-5-5" else "claude-sonnet-5-5"'';
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
      proxy = import ./proxy.nix {
        inherit config;
        codexVersion = pkgs.llm-agents.codex.version;
      };
      mkTunnel = import ./tunnel.nix { inherit pkgs config lib; };
      rea = import ./rea.nix {
        inherit pkgs lib perSystem;
        cfg = cfg.rea;
      };
      video = import ./video/home.nix { inherit pkgs perSystem; };
      iphoneUse = perSystem.self.iphone-use;
      mcp = import ./mcp.nix {
        inherit
          pkgs
          config
          lib
          rea
          video
          iphoneUse
          ;
      };
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
      # agent and its tool shells inherit what they export, so a secret must
      # never go here; a tool that needs one reads it in its own wrapper (see
      # `transcribe`).
      prelude = ''
        export GIT_CONFIG_GLOBAL=${gitConfig}
      '';
      # whisper-1 needs an OpenAI key in the environment of this process
      # alone; the store and the agent that runs it never see the key.
      transcribe = pkgs.writeShellScriptBin "transcribe" ''
        if secret=$(${pkgs.coreutils}/bin/cat "${config.age.secrets.openai-api-key.path}" 2>/dev/null); then
          export OPENAI_API_KEY="$secret"
        fi
        exec ${lib.getExe perSystem.self.transcribe} "$@"
      '';
      # Every skill is a directory holding a SKILL.md, per the Agent Skills
      # standard every harness implements.
      skills =
        lib.mapAttrs (name: _: ./skills + "/${name}") (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
        )
        # Taken from the package so the instructions match the server's tools.
        // lib.optionalAttrs cfg.rea.enable {
          reverse-engineer-anything = "${rea.base}/lib/node_modules/rea-agents/skills/reverse-engineer-anything";
        }
        // lib.optionalAttrs cfg.video.enable video.skills
        // lib.optionalAttrs cfg.iphoneUse.enable {
          iphone-use = "${iphoneUse}/share/iphone-use/skills/iphone-use";
          iphone-use-setup = "${iphoneUse}/share/iphone-use/skills/iphone-use-setup";
        }
        # The search-and-read part of `spark skill` from Spark 1.4.1; compare
        # against a newer CLI's output when its commands change.
        // lib.optionalAttrs cfg.spark.enable { spark = ./spark/skill; };
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
            flake
            proxy
            gitConfig
            mkTunnel
            ;
        })
        (import ./spark/home.nix {
          inherit
            config
            lib
            perSystem
            flake
            mkTunnel
            ;
          hostName = args.osConfig.dotfiles.host.hostName or null;
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
      assertions = [
        {
          # Resolve's MCP server is the macOS app's own, or a Windows program
          # reached through WSL interop. Standalone homes have no osConfig to
          # say this is WSL.
          assertion =
            cfg.video.enable -> pkgs.stdenv.hostPlatform.isDarwin || args.osConfig.dotfiles.host.wsl or false;
          message = "dotfiles.agents.video.enable requires a macOS or WSL host.";
        }
        {
          assertion =
            cfg.t3code.server.tunnel.enable
            -> cfg.t3code.server.enable && cfg.t3code.server.tunnel.hostName != null;
          message = "dotfiles.agents.t3code.server.tunnel.enable requires the server and dotfiles.agents.t3code.server.tunnel.hostName.";
        }
        {
          # Spark Desktop runs only on macOS, and the tunnel's name comes from
          # the host, which standalone homes have no osConfig to supply.
          assertion = cfg.spark.server.enable -> args.osConfig.nixpkgs.hostPlatform.isDarwin or false;
          message = "dotfiles.agents.spark.server.enable requires a nix-darwin host.";
        }
        {
          assertion = cfg.spark.server.enable -> cfg.spark.server.accessAud != null;
          message = "dotfiles.agents.spark.server.enable requires dotfiles.agents.spark.server.accessAud, the AUD tag of the host's Access application.";
        }
      ];

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
        // lib.mergeAttrsList (map (a: a.homeFiles or { }) agents)
        // lib.optionalAttrs cfg.video.enable video.homeFiles;

        # CLIs that shared skills drive; every harness reaches them through PATH.
        packages = [
          transcribe
          perSystem.self.wechat-cli
        ]
        ++ lib.optional cfg.rea.enable rea.package
        ++ lib.optionals cfg.video.enable video.packages
        ++ lib.concatMap (a: a.packages or [ ]) agents;

        shellAliases = lib.mergeAttrsList (map (a: a.shellAliases or { }) agents);

        sessionVariables =
          lib.mergeAttrsList (map (a: a.sessionVariables or { }) agents)
          // lib.optionalAttrs cfg.rea.enable rea.sessionVariables;

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
        # A magpie gateway key, made under Gateway → Gateway keys in its web UI.
        magpie-api-key.file = ../../../secrets/magpie-api-key.age;
        # The gateways are reachable from the public internet through
        # Cloudflare Access; every agent must present the service token.
        cf-access-dotfiles-id.file = ../../../secrets/cf-access-dotfiles-id.age;
        cf-access-dotfiles-secret.file = ../../../secrets/cf-access-dotfiles-secret.age;
        # whisper-1 for `transcribe`; a key restricted to the Audio API.
        openai-api-key.file = ../../../secrets/openai-api-key.age;
      }
      // lib.optionalAttrs (cfg.t3code.server.tunnel.enable || cfg.spark.server.enable) {
        # `cloudflared tunnel login` cert for the tunnels' zone: it creates
        # tunnels and edits any DNS record in that zone.
        cloudflared-cert.file = ../../../secrets/cloudflared-cert.age;
      };
    }
  );
}
