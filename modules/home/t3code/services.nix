# The T3 Code server and its Tailscale route as user services. A plain
# function, so checks/t3-tailnet runs both scripts and inspects their units
# for either platform without evaluating a home.
{
  pkgs,
  lib,
  cfg,
  t3,
  # The policy command that picks the managed policy at each start and
  # restarts the server when it changes (dotfiles.t3code.policy.resolver),
  # or null for none.
  policy ? null,
  profileDirectory,
  homeDirectory,
  # Where the wrapper's resolve keeps status.json, given to the updater too.
  stateHome,
  gitConfig,
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  updatePolicy = cfg.server.enable && policy != null;
  updateInterval = 120;

  # Tailscale Serve and the Cloudflare tunnel both proxy to this loopback port.
  port = 3773;
  tailnetPort = 35338;

  # Service managers start with a bare environment; source the same session
  # variables and profile PATH a login shell would get.
  launchEnvironment = ''
    export PATH=${
      lib.concatStringsSep ":" [
        "${profileDirectory}/bin"
        "/run/wrappers/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ]
    }
    . ${profileDirectory}/etc/profile.d/hm-session-vars.sh
    # T3 sessions arrive without SSH, so no forwarded signing agent ever
    # reaches its git actions or terminal panel; commit unsigned as agents do.
    export GIT_CONFIG_GLOBAL=${gitConfig}
    cd ${lib.escapeShellArg homeDirectory}
  '';

  # The server reads its policy only at startup, and with the path unset it
  # would look for the machine's own. Whatever the resolver does, the server
  # starts, with no policy if none was checked.
  applyPolicy = lib.optionalString (policy != null) ''
    if ! T3CODE_DEV_MANAGED_POLICY_PATH=$(${lib.getExe' pkgs.coreutils "timeout"} 120 ${policy.command} resolve) ||
      [ -z "$T3CODE_DEV_MANAGED_POLICY_PATH" ]; then
      echo "t3code-policy: state=none sha= http=none err=resolver failed; status.json is stale" >&2
      T3CODE_DEV_MANAGED_POLICY_PATH=${policy.none}
    fi
    export T3CODE_DEV_MANAGED_POLICY_PATH
  '';

  serve = pkgs.writeShellScript "t3-serve" (
    launchEnvironment
    + applyPolicy
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
in
{
  inherit port;

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
    // lib.optionalAttrs (updatePolicy && !isDarwin) {
      t3code-policy-update = {
        Unit.Description = "Restart the T3 Code server when its policy changes";
        Service = {
          Type = "oneshot";
          ExecStart = "${policy.command} update";
          Environment = [ "XDG_STATE_HOME=${stateHome}" ];
        };
      };
    };

  systemdUserTimers = lib.optionalAttrs (updatePolicy && !isDarwin) {
    t3code-policy-update = {
      Unit.Description = "Check the T3 Code policy for changes";
      Timer = {
        OnStartupSec = updateInterval;
        OnUnitActiveSec = updateInterval;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };

  launchdAgents =
    lib.optionalAttrs (cfg.server.enable && isDarwin) {
      t3code = {
        enable = true;
        config = {
          ProgramArguments = [ "${serve}" ];
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          StandardOutPath = "${homeDirectory}/Library/Logs/t3code.log";
          StandardErrorPath = "${homeDirectory}/Library/Logs/t3code.log";
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
          StandardOutPath = "${homeDirectory}/Library/Logs/t3code-tailnet.log";
          StandardErrorPath = "${homeDirectory}/Library/Logs/t3code-tailnet.log";
        };
      };
    }
    // lib.optionalAttrs (updatePolicy && isDarwin) {
      t3code-policy-update = {
        enable = true;
        config = {
          ProgramArguments = [
            policy.command
            "update"
          ];
          StartInterval = updateInterval;
          EnvironmentVariables.XDG_STATE_HOME = stateHome;
          StandardOutPath = "${homeDirectory}/Library/Logs/t3code-policy.log";
          StandardErrorPath = "${homeDirectory}/Library/Logs/t3code-policy.log";
        };
      };
    };
}
