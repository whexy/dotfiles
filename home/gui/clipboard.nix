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

    # Path to the SUID wrapper installed by the NixOS vmware-guest module.
    vmwareUserWrapper = "/run/wrappers/bin/vmware-user-suid-wrapper";

    # Two tiny watcher loops form a bidirectional X11<->Wayland clipboard
    # bridge. We avoid `clipboard-sync` (not in nixpkgs) and `wl-clipboard-x11`
    # (one-shot wrapper, not a daemon).
    waylandToX11 = pkgs.writeShellApplication {
      name = "clipboard-wayland-to-x11";
      runtimeInputs = [
        pkgs.wl-clipboard
        pkgs.xclip
      ];
      text = ''
        export DISPLAY=${xDisplay}
        exec wl-paste --watch sh -c '
          data=$(wl-paste --no-newline 2>/dev/null || true)
          [ -z "$data" ] && exit 0
          cur=$(xclip -o -selection clipboard 2>/dev/null || true)
          [ "$data" = "$cur" ] && exit 0
          printf %s "$data" | xclip -i -selection clipboard
        '
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
          ConditionPathExists = vmwareUserWrapper;
        };
        Service = {
          Environment = [ "DISPLAY=${xDisplay}" ];
          ExecStart = vmwareUserWrapper;
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
