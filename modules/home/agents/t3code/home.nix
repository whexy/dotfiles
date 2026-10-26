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

  # Service managers start with a bare environment; source the same session
  # variables and profile PATH a login shell would get.
  serve = pkgs.writeShellScript "t3-serve" (
    ''
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
    ''
    + (
      if cfg.server.tailnet.enable then
        ''
          # A new host starts this service before anyone logs in to the tailnet, and
          # t3 only warns when `tailscale serve` fails, leaving the server
          # unreachable.
          until [ "$(tailscale status --json 2>/dev/null | ${lib.getExe pkgs.jq} -r .BackendState)" = Running ]; do
            sleep 10
          done
          exec ${t3} serve \
            --host 127.0.0.1 --port ${toString port} \
            --tailscale-serve --tailscale-serve-port 35338 --no-browser
        ''
      else
        ''
          exec ${t3} serve --host 127.0.0.1 --port ${toString port} --no-browser
        ''
    )
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

in
{
  packages = [
    t3code
    claudeModels
  ]
  ++ lib.optional cfg.pair.enable perSystem.self.t3-pair;

  sessionVariables = privacyEnv;

  homeFiles = lib.optionalAttrs linkBrowser {
    ${browserDir}.source = browser;
  };

  activation = {
    t3codeClaudeModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe claudeModels}
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
    // lib.optionalAttrs cfg.server.tunnel.enable tunnel.launchdAgents;
}
