{
  pkgs,
  config,
  lib,
  perSystem,
  flake,
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

in
{
  packages = [ t3code ] ++ lib.optional cfg.pair.enable perSystem.self.t3-pair;

  sessionVariables = privacyEnv;

  homeFiles = lib.optionalAttrs linkBrowser {
    ${browserDir}.source = browser;
  };

  # A server that ran before this link existed left its own download here,
  # which Home Manager would otherwise refuse to replace.
  activation = lib.optionalAttrs linkBrowser {
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
