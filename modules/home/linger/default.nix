# Lingering keeps the user's systemd manager running without a session, so
# user services start at boot and outlive a logout. On a headless server a
# daemon stopped by its user's logout fails silently, such as an upgrader
# stranding the host on its generation.
#
# Features that run boot-time user services set `enable`. Only standalone
# Linux homes act on it: a NixOS host's own configuration owns lingering,
# and launchd agents run with the GUI session.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.home.username;
  standalone = (args.osConfig or null) == null;
in
{
  options.dotfiles.linger.enable = lib.mkEnableOption "lingering for this user, which features turn on when they run boot-time user services";

  config =
    lib.mkIf (config.dotfiles.linger.enable && standalone && pkgs.stdenv.hostPlatform.isLinux)
      {
        # logind's polkit policy lets any user linger without authentication; a
        # host that tightens it needs `sudo loginctl enable-linger <user>` once.
        home.activation.enableLinger = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ ! -e /var/lib/systemd/linger/${user} ]; then
            run ${lib.getExe' pkgs.systemd "loginctl"} enable-linger ${lib.escapeShellArg user} ||
              warnEcho "Could not enable lingering: ${user}'s user services stop when ${user} logs out."
          fi
        '';
      };
}
