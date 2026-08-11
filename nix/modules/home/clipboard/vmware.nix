# VMware guest host<->guest clipboard integration for niri/Wayland.
#
# open-vm-tools' dndcp plugin only speaks X11, so we:
#   1. Spawn xwayland-satellite eagerly on a fixed DISPLAY (:0).
#   2. Run vmtoolsd -n vmusr as a user service (the X11 plugin host).
#   3. Bridge the X11 clipboard <-> Wayland clipboard in both directions
#      with two small watcher services.
#
# Returns {} on non-VMware hosts so this file is safe to import
# unconditionally from nix/modules/home/clipboard/default.nix.
args@{
  config,
  pkgs,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.clipboard;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  config = lib.mkIf cfg.vmware.enable (
    let
      isVmware = !isDarwin && osConfig != null && (osConfig.virtualisation.vmware.guest.enable or false);
      xDisplay = ":0";
    in
    if !isVmware then
      { }
    else
      let
        openVmTools = osConfig.virtualisation.vmware.guest.package or pkgs.open-vm-tools;

        # Inner one-shot script: triggered by `wl-paste --watch` on every
        # Wayland clipboard change; mirrors the new content into the X11
        # CLIPBOARD selection. Split out so we don't nest `sh -c '...'` inside
        # writeShellApplication (would trip shellcheck SC2016).
        #
        # Only text/plain is synced: binary payloads (images, rich text) would
        # corrupt under bash's command substitution (which strips NUL bytes)
        # and confuse vmtoolsd's dndcp plugin, breaking the whole chain.
        #
        # `xsel -b -i` forks a background owner of the selection; successive
        # invocations transfer ownership cleanly and fire XFIXES notifications
        # that vmtoolsd's dndcp plugin listens for.
        waylandToX11Once = pkgs.writeShellApplication {
          name = "clipboard-wayland-to-x11-once";
          runtimeInputs = [
            pkgs.wl-clipboard
            pkgs.xsel
          ];
          text = ''
            export DISPLAY=${xDisplay}
            # Skip non-text clipboard payloads.
            wl-paste --list-types 2>/dev/null | grep -q "^text/" || exit 0
            data=$(wl-paste --no-newline --type text/plain 2>/dev/null || true)
            [ -z "$data" ] && exit 0
            cur=$(xsel -b -o 2>/dev/null || true)
            [ "$data" = "$cur" ] && exit 0
            printf %s "$data" | xsel -b -i
          '';
        };

        waylandToX11 = pkgs.writeShellApplication {
          name = "clipboard-wayland-to-x11";
          runtimeInputs = [
            pkgs.wl-clipboard
            waylandToX11Once
          ];
          text = ''
            export DISPLAY=${xDisplay}
            exec wl-paste --watch clipboard-wayland-to-x11-once
          '';
        };

        # `clipnotify` blocks until the X11 CLIPBOARD selection changes, so the
        # loop only does work when there's actually something new from the host.
        # Text-only for symmetry with the Wayland->X11 direction (see above).
        x11ToWayland = pkgs.writeShellApplication {
          name = "clipboard-x11-to-wayland";
          runtimeInputs = [
            pkgs.wl-clipboard
            pkgs.xsel
            pkgs.clipnotify
          ];
          text = ''
            export DISPLAY=${xDisplay}
            while true; do
              clipnotify || sleep 1
              data=$(xsel -b -o 2>/dev/null || true)
              [ -z "$data" ] && continue
              cur=$(wl-paste --no-newline --type text/plain 2>/dev/null || true)
              [ "$data" = "$cur" ] && continue
              printf %s "$data" | wl-copy --type text/plain
            done
          '';
        };

        mkSyncUnit = description: exe: {
          Unit = {
            Description = description;
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = exe;
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      in
      {
        home.packages = with pkgs; [
          xsel
          clipnotify
        ];

        systemd.user.services = {
          # The user-mode vmtoolsd plugin host. Invoked directly rather than via
          # `vmware-user-suid-wrapper`: the wrapper double-forks and exits, which
          # makes systemd lose track of the actual daemon. The wrapper's setuid
          # was only needed for legacy /proc/fs/vmblock access; the fuse mount
          # at /run/vmblock-fuse replaces it.
          vmware-user = {
            Unit = {
              Description = "VMware user agent (clipboard/DnD via XWayland)";
              After = [ "graphical-session.target" ];
              PartOf = [ "graphical-session.target" ];
            };
            Service = {
              Environment = [ "DISPLAY=${xDisplay}" ];
              ExecStart = "${openVmTools}/bin/vmtoolsd -n vmusr";
              Restart = "on-failure";
              RestartSec = 3;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

          clipboard-wayland-to-x11 = mkSyncUnit "Sync Wayland clipboard to X11 (for VMware host integration)" "${waylandToX11}/bin/clipboard-wayland-to-x11";

          clipboard-x11-to-wayland = mkSyncUnit "Sync X11 clipboard to Wayland (for VMware host integration)" "${x11ToWayland}/bin/clipboard-x11-to-wayland";
        };

        # vmtoolsd's dndcp plugin needs a stable X server, so override niri's
        # lazy xwayland-satellite with an eager launch on a known DISPLAY.
        programs.niri.settings = {
          xwayland-satellite.enable = lib.mkForce false;
          environment.DISPLAY = xDisplay;
          spawn-at-startup = [
            {
              command = [
                "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
                xDisplay
              ];
            }
          ];
        };
      }
  );
}
