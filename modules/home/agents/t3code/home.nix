{
  pkgs,
  config,
  lib,
  perSystem,
}:
let
  cfg = config.dotfiles.agents.t3code;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # t3 spawns whichever agent CLIs it finds on PATH. Dropping the bundled
  # providers makes it find the profile's wrapped claude/codex, which carry
  # the model pickers and account credentials the other agent modules set up.
  t3code = pkgs.llm-agents.t3code.override { providerPackages = [ ]; };

  # Every client reaches the server through Tailscale Serve, which proxies to
  # this loopback port.
  port = 3773;

  # Service managers start with a bare environment; source the same session
  # variables and profile PATH a login shell would get.
  serve = pkgs.writeShellScript "t3-serve" ''
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
    cd ${lib.escapeShellArg config.home.homeDirectory}
    exec ${lib.getExe' t3code "t3"} serve \
      --host 127.0.0.1 --port ${toString port} \
      --tailscale-serve --no-browser
  '';

  # The desktop app and `t3 serve` share ~/.t3/userdata, and nothing stops
  # two servers from running on one state directory. Where the service runs,
  # the desktop app starts no backend and is paired with the service like any
  # other host.
  settingsPath = "${config.home.homeDirectory}/.t3/userdata/desktop-settings.json";
  disableDesktopBackend = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings=${lib.escapeShellArg settingsPath}
    run mkdir -p "$(dirname "$settings")"
    current=$(cat "$settings" 2>/dev/null || echo '{}')
    next=$(${lib.getExe pkgs.jq} '.localEnvironmentEnabled = false' <<<"$current")
    if [ "$next" != "$(${lib.getExe pkgs.jq} . <<<"$current")" ]; then
      run ${pkgs.coreutils}/bin/tee "$settings" >/dev/null <<<"$next"
    fi
  '';
in
{
  packages =
    lib.optional cfg.server.enable t3code
    ++ lib.optionals cfg.desktop.enable [
      t3code.desktop
      perSystem.self.t3-pair
    ];

  activation = lib.optionalAttrs (cfg.server.enable && cfg.desktop.enable) {
    t3codeDisableDesktopBackend = disableDesktopBackend;
  };

  systemdUserServices = lib.optionalAttrs (cfg.server.enable && !isDarwin) {
    t3code = {
      Unit.Description = "T3 Code server, published on the tailnet";
      Service = {
        ExecStart = "${serve}";
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  launchdAgents = lib.optionalAttrs (cfg.server.enable && isDarwin) {
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
  };
}
