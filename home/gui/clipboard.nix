# Wayland clipboard persistence, history, and X11<->Wayland bridge (Linux)
#
# wl-clipboard  – provides wl-copy / wl-paste
# cliphist      – clipboard history manager (persists across app exits)
# fuzzel        – Wayland-native app launcher (also used for clipboard picker)
#
# Extra pieces enabled only on VMware guests, where host<->guest copy-paste
# requires:
#   - `vmware-user` running against an XWayland DISPLAY (open-vm-tools only
#     understands X11)
#   - a bidirectional X11 <-> Wayland clipboard bridge, since `vmware-user`
#     drops content into the X11 clipboard but Wayland-native apps cannot
#     read from it.
{
  pkgs,
  lib,
  osConfig,
  darwin,
  ...
}:
if darwin then
  { }
else
  let
    isVmware = osConfig.virtualisation.vmware.guest.enable or false;

    # XWayland-satellite display we pin (see home/gui/niri.nix).
    xDisplay = ":0";

    # open-vm-tools package used by the system (matches the NixOS module so
    # we don't pull a second copy into the closure).
    openVmTools = osConfig.virtualisation.vmware.guest.package or pkgs.open-vm-tools;

    # The user-mode vmtoolsd plugin host. Handles clipboard, DnD, resolution
    # sync, etc. via X11. We invoke it directly rather than via
    # `vmware-user-suid-wrapper` because:
    #   - The wrapper's only purpose was kernel /proc/fs/vmblock access (legacy);
    #     on modern open-vm-tools the vmblock-fuse mount replaces it.
    #   - The wrapper double-forks and detaches, so systemd Type=simple loses
    #     track of the actual daemon and marks the unit "inactive (dead)"
    #     immediately after the wrapper exits, even though vmtoolsd is alive
    #     (but orphaned outside the cgroup).
    # Running vmtoolsd -n vmusr directly keeps it in the unit's cgroup,
    # gives us proper Restart=on-failure handling, and surfaces logs.
    vmwareUserExe = "${openVmTools}/bin/vmtoolsd";

    # Two tiny watcher loops form a bidirectional X11<->Wayland clipboard
    # bridge. We avoid `clipboard-sync` (not in nixpkgs) and `wl-clipboard-x11`
    # (one-shot wrapper, not a daemon).
    #
    # The watcher scripts are split in two:
    #   - an "inner" one-shot script invoked per clipboard change (so we don't
    #     need to nest a `sh -c '...'` inside `wl-paste --watch`, which trips
    #     shellcheck SC2016 inside writeShellApplication);
    #   - an "outer" long-running script that drives the watch loop.
    waylandToX11Once = pkgs.writeShellApplication {
      name = "clipboard-wayland-to-x11-once";
      runtimeInputs = [
        pkgs.wl-clipboard
        pkgs.xclip
      ];
      text = ''
        export DISPLAY=${xDisplay}
        data=$(wl-paste --no-newline 2>/dev/null || true)
        [ -z "$data" ] && exit 0
        cur=$(xclip -o -selection clipboard 2>/dev/null || true)
        [ "$data" = "$cur" ] && exit 0
        printf %s "$data" | xclip -i -selection clipboard
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

    x11ToWayland = pkgs.writeShellApplication {
      name = "clipboard-x11-to-wayland";
      runtimeInputs = [
        pkgs.wl-clipboard
        pkgs.xclip
        pkgs.clipnotify
      ];
      text = ''
        export DISPLAY=${xDisplay}
        # `clipnotify` blocks until the X11 clipboard changes, then exits.
        while true; do
          clipnotify || sleep 1
          data=$(xclip -o -selection clipboard 2>/dev/null || true)
          [ -z "$data" ] && continue
          cur=$(wl-paste --no-newline 2>/dev/null || true)
          [ "$data" = "$cur" ] && continue
          printf %s "$data" | wl-copy
        done
      '';
    };

    # Base services (always on for Linux GUI hosts).
    baseServices = {
      cliphist-watcher = {
        Unit = {
          Description = "Watch Wayland clipboard and store history with cliphist";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };

    # VMware-only services. Require xwayland-satellite spawned on ${xDisplay}
    # at session start (see home/gui/niri.nix).
    vmwareServices = {
      vmware-user = {
        Unit = {
          Description = "VMware user agent (clipboard/DnD via XWayland)";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          Environment = [ "DISPLAY=${xDisplay}" ];
          ExecStart = "${vmwareUserExe} -n vmusr";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      clipboard-wayland-to-x11 = {
        Unit = {
          Description = "Sync Wayland clipboard to X11 (for VMware host integration)";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${waylandToX11}/bin/clipboard-wayland-to-x11";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      clipboard-x11-to-wayland = {
        Unit = {
          Description = "Sync X11 clipboard to Wayland (for VMware host integration)";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${x11ToWayland}/bin/clipboard-x11-to-wayland";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };
  in
  {
    home.packages =
      with pkgs;
      [
        wl-clipboard
        cliphist
        fuzzel
      ]
      ++ lib.optionals isVmware [
        xclip
        clipnotify
      ];

    systemd.user.services = baseServices // lib.optionalAttrs isVmware vmwareServices;
  }
