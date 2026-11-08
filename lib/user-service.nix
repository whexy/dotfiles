# Long-running and periodic user services for both platforms: systemd user
# units on Linux, launchd agents on Darwin. A plain function, so checks can
# build units without evaluating a home.
{
  lib,
  isDarwin,
  homeDirectory,
  # Home Manager's systemd.user.systemctlPath.
  systemctlPath ? "systemctl",
}:
let
  # Home Manager names each launchd agent after its attribute.
  launchdTarget = name: ''"gui/$UID/org.nix-community.home.${name}"'';
  log = name: "${homeDirectory}/Library/Logs/${name}.log";

  normalize =
    name: spec:
    {
      environment = { };
      # Units started, and ordered, before this one; Linux only.
      wants = [ ];
      # Seconds a stop may take before the service is killed.
      stopTimeout = null;
      restartSec = 10;
      log = name;
      # { seconds; description; } runs the command periodically to
      # completion instead of keeping it alive.
      interval = null;
    }
    // spec;

  systemdService =
    s:
    let
      periodic = s.interval != null;
    in
    {
      Unit = {
        Description = s.description;
      }
      // lib.optionalAttrs (s.wants != [ ]) {
        After = s.wants;
        Wants = s.wants;
      };
      Service = {
        ExecStart = lib.escapeShellArgs s.argv;
      }
      // lib.optionalAttrs (s.environment != { }) {
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") s.environment;
      }
      // lib.optionalAttrs (s.stopTimeout != null) { TimeoutStopSec = s.stopTimeout; }
      // (
        if periodic then
          { Type = "oneshot"; }
        else
          {
            Restart = "on-failure";
            RestartSec = s.restartSec;
          }
      );
    }
    // lib.optionalAttrs (!periodic) { Install.WantedBy = [ "default.target" ]; };

  systemdTimer = s: {
    Unit.Description = s.interval.description;
    Timer = {
      OnStartupSec = s.interval.seconds;
      OnUnitActiveSec = s.interval.seconds;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  launchdAgent = s: {
    enable = true;
    config = {
      ProgramArguments = s.argv;
      StandardOutPath = log s.log;
      StandardErrorPath = log s.log;
    }
    // lib.optionalAttrs (s.environment != { }) { EnvironmentVariables = s.environment; }
    // lib.optionalAttrs (s.stopTimeout != null) { ExitTimeOut = s.stopTimeout; }
    // (
      if s.interval != null then
        { StartInterval = s.interval.seconds; }
      else
        {
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
        }
    );
  };
in
{
  # The units for `specs`, an attrset of service name to
  # { description; argv; } plus the optional fields `normalize` lists, as
  # the Home Manager options they set.
  units =
    specs:
    let
      all = lib.mapAttrs normalize specs;
      periodic = lib.filterAttrs (_: s: s.interval != null) all;
    in
    {
      systemd.user.services = lib.optionalAttrs (!isDarwin) (lib.mapAttrs (_: systemdService) all);
      systemd.user.timers = lib.optionalAttrs (!isDarwin) (lib.mapAttrs (_: systemdTimer) periodic);
      launchd.agents = lib.optionalAttrs isDarwin (lib.mapAttrs (_: launchdAgent) all);
    };

  # Shell commands that test whether the service `name` runs, and restart it
  # without waiting for it to come back. On Linux the restart leaves a
  # stopped service stopped; launchd starts one.
  control =
    name:
    if isDarwin then
      {
        running = "/bin/launchctl print ${launchdTarget name} 2>/dev/null | grep 'state = running' >/dev/null";
        restart = "/bin/launchctl kickstart -k ${launchdTarget name}";
      }
    else
      {
        running = "${systemctlPath} --user is-active --quiet ${name}.service";
        restart = "${systemctlPath} --user try-restart --no-block ${name}.service";
      };
}
