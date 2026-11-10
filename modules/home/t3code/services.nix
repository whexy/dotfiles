# The T3 Code server and its Tailscale route as user services. A plain
# function, so checks/t3-tailnet runs both scripts and inspects their units
# for either platform without evaluating a home.
{
  pkgs,
  lib,
  isDarwin,
  cfg,
  # flake.lib.t3's ports: the server's loopback port and Tailscale Serve's.
  port,
  tailnetPort,
  t3,
  # The policy command that picks the managed policy at each start and
  # restarts the server when it changes (dotfiles.t3code.policy.resolver),
  # or null for none.
  policy ? null,
  # The server's public origin, which it builds webhook URLs on, or null for none.
  publicUrl ? null,
  profileDirectory,
  homeDirectory,
  # Where the wrapper's resolve keeps status.json, given to the updater too.
  stateHome,
  gitConfig,
  # The t3-push host token's decrypted path, or null to publish nowhere. Home
  # Manager's agenix path holds a variable the shell expands at start.
  pushTokenPath ? null,
}:
let
  names = import ./units.nix;
  userService = import ../../../lib/user-service.nix { inherit lib isDarwin homeDirectory; };

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

  # A missing or unreadable token starts the server without push.
  applyPush = lib.optionalString (pushTokenPath != null) ''
    if T3CODE_PUSH_TOKEN=$(${lib.getExe' pkgs.coreutils "cat"} "${pushTokenPath}" 2>/dev/null) &&
      [ -n "$T3CODE_PUSH_TOKEN" ]; then
      export T3CODE_PUSH_URL=https://t3-push.clusters.work T3CODE_PUSH_TOKEN
    else
      echo "t3-push: host token unreadable; publishing nowhere" >&2
      unset T3CODE_PUSH_TOKEN
    fi
  '';

  serve = pkgs.writeShellScript "t3-serve" (
    launchEnvironment
    + applyPolicy
    + applyPush
    + ''
      ${lib.optionalString (publicUrl != null) "export T3CODE_PUBLIC_URL=${lib.escapeShellArg publicUrl}"}
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
userService.units (
  lib.optionalAttrs cfg.server.enable {
    ${names.server} = {
      description = "T3 Code server";
      argv = [ "${serve}" ];
    };
  }
  // lib.optionalAttrs (cfg.server.enable && cfg.server.tailnet.enable) {
    ${names.tailnet} = {
      description = "T3 Code Tailscale route";
      argv = [ "${tailnet}" ];
      stopTimeout = 30;
    };
  }
  // lib.optionalAttrs (cfg.server.enable && policy != null) {
    ${names.policyUpdate} = {
      description = "Restart the T3 Code server when its policy changes";
      argv = [
        policy.command
        "update"
      ];
      environment.XDG_STATE_HOME = stateHome;
      log = "t3code-policy";
      interval = {
        seconds = 120;
        description = "Check the T3 Code policy for changes";
      };
    };
  }
)
