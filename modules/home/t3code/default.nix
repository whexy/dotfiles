# T3 Code: its server, published on the tailnet and through a public tunnel,
# the desktop app, the t3-pair helper, and the SSH device host.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  inherit (config.dotfiles.tunnels) hostName;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # The nightly server package contains only T3's server runtime. Provider
  # CLIs remain on the Home Manager profile PATH with their existing wrappers.
  t3code = if cfg.package == null then perSystem.self.t3code-nightly else cfg.package;

  # T3 treats an executable at this path as its installed preview browser; the
  # package's patched copy replaces the download that cannot run on NixOS.
  browser = t3code.browser or null;
  browserDir = ".t3/tools/chrome-headless-shell/${browser.platform}/${browser.version}";
  linkBrowser = cfg.server.enable && browser != null;

  t3 = lib.getExe' t3code "t3";

  json = pkgs.formats.json { };
  policyCfg = config.programs.t3code.policy;

  # The `t3` that loads the policy checks it first; it is the only check, as
  # the option itself is plain JSON.
  policy =
    if policyCfg == { } then
      null
    else
      let
        unchecked = json.generate "t3code-policy-unchecked.json" policyCfg;
      in
      pkgs.runCommand "t3code-policy.json" { } ''
        HOME=$TMPDIR ${t3} policy check ${unchecked} >&2
        cp ${unchecked} $out
      '';

  # Release builds ignore T3CODE_DEV_MANAGED_POLICY_PATH; a package whose
  # server reads it says so with passthru.honorsManagedPolicyPath.
  policyApplied = policy != null && (t3code.honorsManagedPolicyPath or false);

  services = import ./services.nix {
    inherit
      pkgs
      lib
      cfg
      t3
      policy
      ;
    inherit (config.home) profileDirectory homeDirectory;
    inherit (config.dotfiles.agents.launcher) gitConfig;
  };

  # The server reads these from its own environment, and the desktop app
  # forwards the telemetry flag from the login shell to the server it bundles.
  # Home Manager exports session variables into both the login shell and the
  # systemd user environment, which is how each surface receives them.
  privacyEnv = {
    T3CODE_TELEMETRY_ENABLED = "false";
    # Also overrides the standard OTEL_SDK_DISABLED, so an OTLP endpoint set
    # elsewhere still exports nothing.
    T3CODE_OTEL_SDK_DISABLED = "true";
    # The local NDJSON trace file cannot be switched off, only emptied.
    T3CODE_TRACE_MIN_LEVEL = "None";
    T3CODE_TRACE_MAX_FILES = "1";
    T3CODE_TRACE_MAX_BYTES = "65536";
  };

  # T3's Claude provider lists only Claude's own models. It starts Claude Code
  # through the `claude` launcher, which sends any model to the gateway Claude
  # Code is set to, so the provider's custom models add every other model that
  # CLIProxyAPI, Claude Code's default gateway, serves. They fail while
  # claude-select names another gateway or the claude.ai login. Claude's own
  # models stay T3's, whose catalog knows their options.
  #
  # dotfiles-settings.json beside T3's settings records the models this wrote,
  # so models the gateway drops are removed and ones added in T3 survive.
  claudeModels =
    let
      gateway = config.dotfiles.llmGateways.gateways.cliproxyapi;
      inherit (config.dotfiles.llmGateways) accessToken;
      jq = lib.getExe pkgs.jq;
    in
    pkgs.writeShellScriptBin "t3-claude-models" ''
      set -eo pipefail
      userdata=${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata"}
      settings="$userdata/settings.json"
      state="$userdata/dotfiles-settings.json"

      # The agenix paths expand XDG_RUNTIME_DIR, which an activation outside
      # the user's session lacks; the reads then fail and the list stays.
      # Credentials reach curl on stdin, never on its command line.
      if ! key=$(<"${gateway.apiKeyPath}") ||
        ! accessId=$(<"${accessToken.idPath}") ||
        ! accessSecret=$(<"${accessToken.secretPath}") ||
        ! catalog=$(
          printf 'Authorization: Bearer %s\nCF-Access-Client-Id: %s\nCF-Access-Client-Secret: %s\n' \
            "$key" "$accessId" "$accessSecret" |
            ${lib.getExe pkgs.curl} --fail --silent --show-error --max-time 10 \
              --header @- ${lib.escapeShellArg gateway.catalogUrl}
        ); then
        echo "t3-claude-models: could not list ${gateway.name}'s models; T3 Code's Claude models are unchanged" >&2
        exit 0
      fi

      # The catalog is Codex's, so it also lists effort levels Claude Code
      # does not take.
      if ! models=$(${jq} -c '
        {low: "Low", medium: "Medium", high: "High", xhigh: "Extra High", max: "Max"} as $labels
        | [.models[]
            | select(.visibility != "hide" and (.slug | startswith("claude-") | not))
            | .default_reasoning_level as $default
            | {
                slug,
                name: (.display_name // .slug),
                capabilities: {
                  optionDescriptors: [
                    [.supported_reasoning_levels[]?.effort | select($labels[.] != null)]
                    | select(length > 0)
                    | {
                        id: "effort",
                        label: "Reasoning",
                        type: "select",
                        options: map({id: ., label: $labels[.]} + (if . == $default then {isDefault: true} else {} end))
                      }
                  ]
                }
              }]
      ' <<<"$catalog"); then
        echo "t3-claude-models: ${gateway.name} answered without a model catalog; T3 Code's Claude models are unchanged" >&2
        exit 0
      fi

      read_settings() {
        if [ -e "$settings" ]; then
          cat "$settings"
        else
          echo '{}'
        fi
      }

      mkdir -p "$userdata"
      before=$(read_settings)
      owned=$(${jq} -c '.ownedClaudeModels // []' "$state" 2>/dev/null) || owned='[]'
      if ! after=$(${jq} --argjson models "$models" --argjson owned "$owned" '
        ($owned + [$models[].slug]) as $replaced
        | .providerInstances.claudeAgent |= (
            (. // {driver: "claudeAgent"})
            | .config.customModels |= (
                [(. // [])[]
                  | select((if type == "string" then . else .slug end) as $slug
                      | any($replaced[]; . == $slug) | not)]
                + $models
              )
          )
      ' <<<"$before"); then
        echo "t3-claude-models: could not update $settings; leaving it unchanged" >&2
        exit 0
      fi

      replace() {
        local temporary
        temporary=$(mktemp "$userdata/.$(basename "$1").XXXXXX")
        printf '%s\n' "$2" >"$temporary"
        chmod 644 "$temporary"
        mv "$temporary" "$1"
      }

      # T3 rebuilds its Claude provider whenever its settings change, so an
      # unchanged list is not written. T3 also rewrites the file itself, so a
      # file it changed meanwhile is left for the next run.
      if ! ${jq} -e --argjson after "$after" '. == $after' <<<"$before" >/dev/null; then
        if [ "$(read_settings)" != "$before" ]; then
          echo "t3-claude-models: $settings changed while editing; run t3-claude-models again" >&2
          exit 0
        fi
        replace "$settings" "$after"
      fi
      replace "$state" "$(${jq} -n --argjson models "$models" '{ownedClaudeModels: [$models[].slug]}')"
    '';

  # Sets one key of a JSON document in T3's userdata, keeping the keys T3
  # wrote there.
  userdataSetting =
    {
      name,
      file,
      key,
      value,
    }:
    let
      jq = lib.getExe pkgs.jq;
      json = lib.escapeShellArg (builtins.toJSON value);
    in
    pkgs.writeShellScriptBin name ''
      set -eo pipefail
      userdata=${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata"}
      document="$userdata/${file}"
      if ${jq} -e --argjson value ${json} '.${key} == $value' "$document" >/dev/null 2>&1; then
        exit 0
      fi
      if [ ! -e "$document" ]; then
        after=$(${jq} -n --argjson value ${json} '{${key}: $value}')
      elif ! after=$(${jq} --argjson value ${json} '.${key} = $value' "$document"); then
        echo "${name}: could not update $document; leaving it unchanged" >&2
        exit 0
      fi
      mkdir -p "$userdata"
      temporary=$(mktemp "$userdata/.${file}.XXXXXX")
      printf '%s\n' "$after" >"$temporary"
      chmod 644 "$temporary"
      mv "$temporary" "$document"
    '';

  # The policy locks linked environments on. Until the server applies the
  # policy, activation writes the setting instead; the running server reloads
  # settings.json when it changes.
  linkedEnvironments = userdataSetting {
    name = "t3-linked-environments";
    file = "settings.json";
    key = "linkedEnvironmentsEnabled";
    value = true;
  };

  # The desktop app's own server needs ~/.t3/userdata to itself, and the app
  # quits when the server service already holds it. Where the service runs,
  # the app starts no local environment and is a client of that server
  # instead, paired with t3-pair.
  desktopClientOnly = userdataSetting {
    name = "t3-desktop-client-only";
    file = "desktop-settings.json";
    key = "localEnvironmentEnabled";
    value = false;
  };

  # T3's updater replaces the macOS app itself, so activation installs it only
  # when it is missing, at the nightly the server runs. Installing as the user
  # lets the updater run without an admin prompt.
  desktopApp = "/Applications/T3 Code (Nightly).app";
  installDesktopApp =
    let
      inherit (perSystem.self.t3code-nightly) version;
    in
    pkgs.writeShellApplication {
      name = "t3code-desktop-install";
      text = ''
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT

        /usr/bin/curl -fsSL --retry 3 --connect-timeout 30 --speed-limit 10240 --speed-time 60 \
          -o "$tmp/T3.zip" \
          https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-arm64.zip
        /usr/bin/ditto -x -k "$tmp/T3.zip" "$tmp"

        # Nothing pins the archive's hash, so only T3 Tools' Developer ID
        # vouches for what gets installed.
        /usr/bin/codesign --verify --deep --strict \
          -R='anchor apple generic and identifier "com.t3tools.t3code" and certificate leaf[subject.OU] = "ARK85ZXQ4Z"' \
          "$tmp/T3 Code (Nightly).app"
        mv "$tmp/T3 Code (Nightly).app" ${lib.escapeShellArg desktopApp}
      '';
    };
in
{
  # Home Manager's own programs.t3code installs a package and merges
  # settings; the policy applies to the server dotfiles.t3code runs.
  options.programs.t3code.policy = lib.mkOption {
    inherit (json) type;
    default = { };
    description = ''
      The T3 Code managed policy for the server dotfiles.t3code runs, as T3's
      JSON document; empty means none. Setting paths are literal dotted keys.
      The server reads it from the Nix store, where agents running as the
      user cannot change it, and restarts when it changes. Only builds that
      honor `T3CODE_DEV_MANAGED_POLICY_PATH` apply it.
    '';
  };

  options.dotfiles.t3code = {
    enable = lib.mkEnableOption "T3 Code, the web GUI for coding agents, and its Claude gateway models";
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
          default = cfg.server.enable;
          defaultText = lib.literalExpression "config.dotfiles.t3code.server.enable";
          description = ''
            Whether to publish the server on the public internet through a
            Cloudflare tunnel at the host's `flake.lib.publicHost "t3"` name. The
            host creates its own tunnel and DNS record on first start with the
            shared `cloudflared-cert` secret. The server's own pairing is the
            only gate in front of it.
          '';
        };
      };
    };
    deviceHost.enable = lib.mkOption {
      type = lib.types.bool;
      # A Mac that manages Xcode has the simulators other T3 servers drive.
      default = args.osConfig.dotfiles.system.xcodes.enable or false;
      defaultText = lib.literalExpression "osConfig.dotfiles.system.xcodes.enable or false";
      description = ''
        Whether this machine serves as a T3 Code SSH device host, whose iOS
        simulators other T3 servers drive over SSH. Their probe and device
        tools run `node` from the non-interactive SSH PATH, so this puts
        Node.js on the profile.
      '';
    };
    pair.enable = lib.mkEnableOption "the t3-pair helper, which mints pairing URLs for T3 Code servers";
    desktop.enable = lib.mkEnableOption ''
      the T3 Code desktop app. Where this host runs the server, the app has
      no local environment of its own and connects to that server once
      paired with `t3-pair`
    '';
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = policyCfg != { } -> cfg.enable && cfg.server.enable;
          message = "programs.t3code.policy applies only to the server dotfiles.t3code.server runs.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.server.tunnel.enable -> cfg.server.enable && hostName != null;
          message = "dotfiles.t3code.server.tunnel.enable requires the server and dotfiles.tunnels.hostName.";
        }
      ];

      age.secrets = config.dotfiles.llmGateways.secrets;

      # Each key is a default a home replaces on its own. Locked: linked
      # environments, which the cluster's MCP hub (clusters-work
      # gitops/apps/t3code-hub) needs to link to every server, and provider
      # update checks, as Nix pins the provider CLIs. The rest are preferences
      # the user's own choices override. Telemetry also stays off in the
      # environment, for the desktop app and for servers that ignore the
      # policy. The Claude provider instance stays out: t3-claude-models
      # rewrites its models, and T3 locks an instance only as a whole.
      programs.t3code.policy = lib.mkIf cfg.server.enable (
        lib.mapAttrsRecursive (_: lib.mkDefault) {
          schemaVersion = 1;
          organization = "dotfiles";
          limits.telemetry = false;
        }
        // {
          settings =
            lib.mapAttrs (_: lib.mkDefault) {
              "linkedEnvironmentsEnabled" = {
                value = true;
                locked = true;
              };
              "enableProviderUpdateChecks" = {
                value = false;
                locked = true;
              };
            }
            //
              lib.mapAttrs
                (
                  _: value:
                  lib.mkDefault {
                    inherit value;
                    locked = false;
                  }
                )
                {
                  "storageCleanup.worktreeAfterDays" = 8;
                  "storageCleanup.worktreeOnMerge" = true;
                  "storageCleanup.worktreeOnDelete" = true;
                  "storageCleanup.worktreeUnchanged" = true;
                  "storageCleanup.browserArtifactsAfterDays" = 8;
                  "storageCleanup.logsAfterDays" = 8;
                  "defaultAutoPull" = true;
                  "idleCompaction" = "beforeCacheExpires";
                  "snoozeLimitedThreads" = true;
                  "autoResumeLimitedThreads" = true;
                  "sidebarAutoSettleOnMerge" = false;
                  "branchNamingMode" = "semantic";
                  "branchNamePrefix" = "whexy/";
                  "pullRequestMergeMethod" = "rebase";
                };
        }
      );

      home = {
        packages = [
          t3code
          claudeModels
        ]
        ++ lib.optional cfg.pair.enable perSystem.self.t3-pair
        ++ lib.optional (cfg.desktop.enable && !isDarwin) perSystem.self.t3code-desktop-nightly
        # pkgs.nodejs rather than a pinned major: editor.javascript installs it
        # too, and two different nodes would collide in the profile.
        ++ lib.optional cfg.deviceHost.enable pkgs.nodejs;

        sessionVariables = privacyEnv;

        file = lib.optionalAttrs linkBrowser {
          ${browserDir}.source = browser;
        };

        activation = {
          t3codeClaudeModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${lib.getExe claudeModels}
          '';
        }
        // lib.optionalAttrs (cfg.server.enable && !policyApplied) {
          t3codeLinkedEnvironments = lib.hm.dag.entryAfter [ "t3codeClaudeModels" ] ''
            run ${lib.getExe linkedEnvironments}
          '';
        }
        // lib.optionalAttrs (cfg.desktop.enable && cfg.server.enable) {
          t3codeDesktopClientOnly = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${lib.getExe desktopClientOnly}
          '';
        }
        // lib.optionalAttrs (cfg.desktop.enable && isDarwin) {
          t3codeDesktopApp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if [ ! -e ${lib.escapeShellArg desktopApp} ]; then
              run ${lib.getExe installDesktopApp} || warnEcho "T3 Code was not installed; the next activation retries"
            fi
          '';
        }
        # A server that ran before this link existed left its own download here,
        # which Home Manager would otherwise refuse to replace.
        // lib.optionalAttrs linkBrowser {
          t3codeBrowser = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
            browser="$HOME/${browserDir}"
            if [ -d "$browser" ] && [ ! -L "$browser" ]; then
              run rm -rf $VERBOSE_ARG "$browser"
            fi
          '';
        };
      };

      systemd.user.services = services.systemdUserServices;
      launchd.agents = services.launchdAgents;

      dotfiles.tunnels.services.t3code-tunnel = lib.mkIf cfg.server.tunnel.enable (
        let
          hostname = flake.lib.publicHost "t3" hostName;
        in
        {
          tunnel = "t3-${hostName}";
          inherit hostname;
          inherit (services) port;
          description = "Cloudflare tunnel publishing the T3 Code server at ${hostname}";
        }
      );
    })
  ];
}
