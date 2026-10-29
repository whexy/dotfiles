{
  pkgs,
  config,
  lib,
  perSystem,
  flake,
  proxy,
  gitConfig,
  mkTunnel,
}:
let
  cfg = config.dotfiles.agents.t3code;
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

  # Tailscale Serve and the Cloudflare tunnel both proxy to this loopback port.
  port = 3773;
  tailnetPort = 35338;

  # Service managers start with a bare environment; source the same session
  # variables and profile PATH a login shell would get.
  launchEnvironment = ''
    export PATH=${
      lib.concatStringsSep ":" [
        "${config.home.profileDirectory}/bin"
        "/run/wrappers/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ]
    }
    . ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh
    # T3 sessions arrive without SSH, so no forwarded signing agent ever
    # reaches its git actions or terminal panel; commit unsigned as agents do.
    export GIT_CONFIG_GLOBAL=${gitConfig}
    cd ${lib.escapeShellArg config.home.homeDirectory}
  '';

  serve = pkgs.writeShellScript "t3-serve" (
    launchEnvironment
    + ''
      exec ${t3} serve --host 127.0.0.1 --port ${toString port} --no-browser ${lib.optionalString cfg.server.tailnet.enable "--tailscale-serve --tailscale-serve-port ${toString tailnetPort}"}
    ''
  );

  # Keep T3's Serve flag for dynamic environment discovery. Its initial setup
  # may fail while Tailscale is offline; this independent service repairs only
  # T3's HTTPS root handler, preserving other ports and paths.
  tailnet = pkgs.writeShellScript "t3-tailnet" (
    launchEnvironment
    + ''
      export PATH=${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.jq
        ]
      }:"$PATH"
    ''
    + ''
      backend=http://127.0.0.1:${toString port}
      serve_port=${toString tailnetPort}
    ''
    + builtins.readFile ./tailnet.sh
  );

  tunnel =
    let
      hostname = flake.lib.publicHost "t3" cfg.server.tunnel.hostName;
    in
    mkTunnel {
      name = "t3code-tunnel";
      tunnel = "t3-${cfg.server.tunnel.hostName}";
      inherit hostname port;
      description = "Cloudflare tunnel publishing the T3 Code server at ${hostname}";
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
      gateway = proxy.gateways.cliproxyapi;
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
        ! accessId=$(<"${proxy.cfAccessIdPath}") ||
        ! accessSecret=$(<"${proxy.cfAccessSecretPath}") ||
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

  # Linked environments is a Labs setting, off by default, and a server with it
  # off refuses links. Every server turns it on so the cluster's MCP hub
  # (clusters-work gitops/apps/t3code-hub) can link to it. The running server
  # reloads settings.json when it changes.
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
  packages = [
    t3code
    claudeModels
  ]
  ++ lib.optional cfg.pair.enable perSystem.self.t3-pair
  ++ lib.optional (cfg.desktop.enable && !isDarwin) perSystem.self.t3code-desktop-nightly;

  sessionVariables = privacyEnv;

  homeFiles = lib.optionalAttrs linkBrowser {
    ${browserDir}.source = browser;
  };

  activation = {
    t3codeClaudeModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe claudeModels}
    '';
  }
  // lib.optionalAttrs cfg.server.enable {
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

  systemdUserServices =
    lib.optionalAttrs (cfg.server.enable && !isDarwin) {
      t3code = {
        Unit.Description = "T3 Code server";
        Service = {
          ExecStart = "${serve}";
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };
    }
    // lib.optionalAttrs (cfg.server.enable && cfg.server.tailnet.enable && !isDarwin) {
      t3code-tailnet = {
        Unit.Description = "T3 Code Tailscale route";
        Service = {
          ExecStart = "${tailnet}";
          TimeoutStopSec = 30;
          Restart = "on-failure";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };
    }
    // lib.optionalAttrs cfg.server.tunnel.enable tunnel.systemdUserServices;

  launchdAgents =
    lib.optionalAttrs (cfg.server.enable && isDarwin) {
      t3code = {
        enable = true;
        config = {
          ProgramArguments = [ "${serve}" ];
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/t3code.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/t3code.log";
        };
      };
    }
    // lib.optionalAttrs (cfg.server.enable && cfg.server.tailnet.enable && isDarwin) {
      t3code-tailnet = {
        enable = true;
        config = {
          ProgramArguments = [ "${tailnet}" ];
          ExitTimeOut = 30;
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/t3code-tailnet.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/t3code-tailnet.log";
        };
      };
    }
    // lib.optionalAttrs cfg.server.tunnel.enable tunnel.launchdAgents;
}
