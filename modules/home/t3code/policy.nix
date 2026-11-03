# The managed policy the T3 Code server applies. No policy lives here: the
# server's wrapper runs `t3code-policy resolve` at each start, which fetches
# it from `policy.url`, checks it with the server's own binary, and keeps the
# last good copy for when the URL is unreachable. A timer runs
# `t3code-policy update`, which restarts the server when the policy changes.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # The services.nix units: Home Manager names the launchd agent
  # org.nix-community.home.<name>.
  launchdTarget = ''"gui/$UID/org.nix-community.home.t3code"'';
  systemctl = "${config.systemd.user.systemctlPath} --user";
  # Bounded, so the updater releases the lock the wrapper waits for.
  server =
    if isDarwin then
      {
        running = "timeout 5 /bin/launchctl print ${launchdTarget} 2>/dev/null | grep 'state = running' >/dev/null";
        restart = "timeout 10 /bin/launchctl kickstart -k ${launchdTarget}";
      }
    else
      {
        running = "timeout 5 ${systemctl} is-active --quiet t3code.service";
        # try-restart leaves a server stopped since the last check stopped;
        # --no-block, as the new wrapper waits for the lock this run holds.
        restart = "timeout 10 ${systemctl} try-restart --no-block t3code.service";
      };

  # With the path unset, T3 would look for the machine's own policy; a path
  # set to a file that cannot exist means no policy at all.
  none = "${pkgs.emptyDirectory}/policy.json";

  command = import ./policy-command.nix {
    inherit
      pkgs
      lib
      none
      server
      ;
    inherit (cfg.policy) url;
    t3 = lib.getExe' cfg.finalPackage "t3";
    editorUrl = "https://t3-policy.at-basking.ts.net/";
  };
in
{
  options.dotfiles.t3code.policy = {
    url = lib.mkOption {
      type = lib.types.str;
      default = "https://t3-policy.clusters.work/dotfiles.json";
      description = ''
        The managed policy this host's T3 Code server follows. The server
        fetches it at each start; a timer checks it every 2 minutes and
        restarts the server when it changes.
      '';
    };
    resolver = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      internal = true;
      readOnly = true;
      default = {
        command = lib.getExe command;
        inherit none;
      };
      description = "The policy command the server's wrapper and updater run, and the path that means no policy.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.server.enable) {
    home.packages = [ command ];
  };
}
