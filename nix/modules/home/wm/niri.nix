# Niri Wayland compositor configuration (Linux)
# Note: inputs.niri.homeModules.niri is imported by ./default.nix
# (this file is gated on dotfiles.gui.enable and cannot declare imports).
args@{
  config,
  pkgs,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.wm;
in
{
  config = lib.mkIf cfg.niri.enable (
    let
      monitors = osConfig.dotfiles.hardware.monitors or [ ];

      # Build programs.niri.settings.outputs from dotfiles.hardware.monitors entries.
      # Each entry maps to a niri output block with mode, refresh, and scale.
      niriOutputs = lib.listToAttrs (
        map (m: {
          name = m.connector;
          value = lib.filterAttrs (_: v: v != null) {
            mode = lib.optionalAttrs (m.resolution != null) {
              inherit (m.resolution) width;
              inherit (m.resolution) height;
              refresh = m.refreshRate; # null → niri picks highest for the resolution
            };
            inherit (m) scale;
          };
        }) monitors
      );

      # Script to apply scale 1.5 to any output not covered by dotfiles.hardware.monitors.
      fallbackScaleScript = pkgs.writeShellApplication {
        name = "niri-fallback-scale";
        runtimeInputs = [
          config.programs.niri.package
          pkgs.jq
        ];
        text =
          let
            connector_list = "(${lib.concatMapStringsSep " " (c: ''"${c}"'') (map (m: m.connector) monitors)})";
          in
          ''
            sleep 1
            declared=${connector_list}
            for output in $(niri msg --json outputs | jq -r '.[].name'); do
              skip=0
              for d in "''${declared[@]}"; do
                [ "$output" = "$d" ] && skip=1 && break
              done
              [ "$skip" = "0" ] && niri msg output "$output" scale 1.5
            done
          '';
      };
    in
    {
      home.packages = with pkgs; [
        wl-clipboard
      ];

      programs.niri = {
        enable = true;
        # Use the niri from our nixpkgs (currently 25.11) instead of the niri-flake's
        # pinned niri-stable (currently 25.08), so we get a single cache-hit niri and
        # avoid pulling an extra rebuild-from-source derivation into the closure.
        package = pkgs.niri;
      };
      services = {
        wl-clip-persist.enable = true;
        blueman-applet.enable = true;
      };

      # Turn off all monitors after 5 minutes of inactivity via swayidle.
      # swayidle listens to the Wayland idle protocol and runs commands on timeout.
      # `niri msg action power-off-monitors` uses niri's built-in DPMS control.
      # On resume (any input event), niri automatically powers monitors back on.
      services.swayidle = {
        enable = true;
        timeouts = [
          {
            timeout = 300; # 5 minutes
            command = "${config.programs.niri.package}/bin/niri msg action power-off-monitors";
          }
        ];
      };

      # Niri settings
      programs.niri.settings = {
        # Skip the hotkey overlay on startup (we have custom binds)
        hotkey-overlay.skip-at-startup = true;

        # Static output configuration derived from dotfiles.hardware.monitors declarations.
        # Connectors not listed there fall back to the IPC script below.
        outputs = niriOutputs;

        # XWayland support for X11 apps that don't support Wayland natively.
        # xwayland-satellite runs as a separate process and provides a rootless XWayland
        # server; it starts lazily when an X11 app first requests DISPLAY.
        xwayland-satellite = {
          enable = true;
          path = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
        };

        spawn-at-startup = [
          # Fallback: apply scale 1.5 to any output not covered by dotfiles.hardware.monitors.
          # On machines with full dotfiles.hardware.monitors declarations this loop is a no-op.
          {
            command = [ "${fallbackScaleScript}/bin/niri-fallback-scale" ];
          }
          # Input method framework (fcitx5) – needs explicit launch since niri
          # doesn't process XDG autostart entries.
          {
            command = [
              "fcitx5"
              "-d"
            ];
          }
        ];

        # Transparent workspace background
        layout.background-color = "#00000000";

        # Thin focus ring (niri default is 4)
        layout.focus-ring.width = 1;

        # Fast key repeat for smooth Vim navigation
        input.keyboard.repeat-delay = 200;
        input.keyboard.repeat-rate = 40;

        binds =
          let
            # Modifier prefixes matching Karabiner setup via kanata:
            #   CapsLock (held) = Hyper = Ctrl+Alt+Shift+Super
            #   Tab (held)      = Meh   = Ctrl+Alt+Super
            hyper = "Ctrl+Alt+Shift+Super";
            meh = "Ctrl+Alt+Super";
          in
          {
            # ── Focus (Hyper + vim keys) ───────────────────────────────
            "${hyper}+H".action.focus-column-left = [ ];
            "${hyper}+J".action.focus-window-down = [ ];
            "${hyper}+K".action.focus-window-up = [ ];
            "${hyper}+L".action.focus-column-right = [ ];

            # Focus back-and-forth between workspaces
            "${hyper}+Tab".action.focus-workspace-previous = [ ];

            # Focus workspace by index (Hyper + number)
            "${hyper}+1".action.focus-workspace = 1;
            "${hyper}+2".action.focus-workspace = 2;
            "${hyper}+3".action.focus-workspace = 3;
            "${hyper}+4".action.focus-workspace = 4;
            "${hyper}+5".action.focus-workspace = 5;
            "${hyper}+6".action.focus-workspace = 6;
            "${hyper}+7".action.focus-workspace = 7;
            "${hyper}+8".action.focus-workspace = 8;
            "${hyper}+9".action.focus-workspace = 9;

            # ── Move window (Meh + vim keys) ──────────────────────────
            "${meh}+H".action.move-column-left = [ ];
            "${meh}+J".action.move-window-down = [ ];
            "${meh}+K".action.move-window-up = [ ];
            "${meh}+L".action.move-column-right = [ ];

            # Move window to workspace by index (Meh + number)
            "${meh}+1".action.move-column-to-workspace = 1;
            "${meh}+2".action.move-column-to-workspace = 2;
            "${meh}+3".action.move-column-to-workspace = 3;
            "${meh}+4".action.move-column-to-workspace = 4;
            "${meh}+5".action.move-column-to-workspace = 5;
            "${meh}+6".action.move-column-to-workspace = 6;
            "${meh}+7".action.move-column-to-workspace = 7;
            "${meh}+8".action.move-column-to-workspace = 8;
            "${meh}+9".action.move-column-to-workspace = 9;

            # Move column to adjacent monitor (Meh + arrow keys)
            "${meh}+Left".action.move-column-to-monitor-left = [ ];
            "${meh}+Right".action.move-column-to-monitor-right = [ ];

            # ── Layout & Resize (Meh +) ──────────────────────────────
            # Fullscreen (matches Meh+F from AeroSpace)
            "${meh}+F".action.fullscreen-window = [ ];

            # Resize column width (matches Meh+minus/equal from AeroSpace)
            "${meh}+Minus".action.set-column-width = "-10%";
            "${meh}+Equal".action.set-column-width = "+10%";

            # Cycle preset column widths (matches Meh+/ from AeroSpace)
            "${meh}+Slash".action.switch-preset-column-width = [ ];

            # Column management (niri-specific, similar to AeroSpace join-with)
            "${meh}+Comma".action.consume-window-into-column = [ ];
            "${meh}+Period".action.expel-window-from-column = [ ];
            "${meh}+BracketLeft".action.consume-or-expel-window-left = [ ];
            "${meh}+BracketRight".action.consume-or-expel-window-right = [ ];

            # Toggle floating (matches AeroSpace service mode "f")
            "${hyper}+F".action.toggle-window-floating = [ ];
            "${hyper}+V".action.switch-focus-between-floating-and-tiling = [ ];

            # Toggle stacking ("Tabs")
            "${hyper}+S".action.toggle-column-tabbed-display = [ ];

            # Center column
            "${meh}+C".action.center-column = [ ];

            # Maximize column (fill width without going fullscreen)
            "${meh}+M".action.maximize-column = [ ];

            # ── Launcher & Clipboard (Hyper +) ───────────────────────
            # App launcher (fuzzel)
            "${hyper}+Space" = {
              action.spawn = "fuzzel";
              repeat = false;
            };
            "${meh}+Space" = {
              action.spawn = "fuzzel";
              repeat = false;
            };

            # Clipboard history picker
            "${hyper}+C" = {
              action.spawn = [
                "sh"
                "-c"
                "cliphist list | fuzzel -d | cliphist decode | wl-copy"
              ];
              repeat = false;
            };

            # ── Essentials (Hyper +) ──────────────────────────────────
            # Terminal: use `ghostty +new-window` so new windows go through D-Bus
            # activation (com.mitchellh.ghostty) instead of spawning a plain
            # process. This makes Ghostty run as the `app-com.mitchellh.ghostty`
            # systemd user service, giving instant window creation, single-instance
            # semantics, and a running unit so `systemctl reload --user
            # app-com.mitchellh.ghostty.service` (used by ghostty-toggle-theme)
            # actually works.
            #
            # With ssh window multiplexing the spawn goes through `ssh-window
            # launch` instead, which clones the focused window's SSH context;
            # its niri backend keeps the same `+new-window` D-Bus activation.
            "${hyper}+T" = {
              action.spawn =
                if config.dotfiles.ssh.windowMultiplexing.enable then
                  [
                    "${config.programs.ssh-window.package}/bin/ssh-window"
                    "launch"
                  ]
                else
                  [
                    "ghostty"
                    "+new-window"
                  ];
              repeat = false;
            };

            # Close window
            "${hyper}+Q" = {
              action.close-window = [ ];
              repeat = false;
            };

            # Show hotkey overlay
            "${hyper}+Slash".action.show-hotkey-overlay = [ ];

            # Overview (global view)
            "${hyper}+O" = {
              action.toggle-overview = [ ];
              repeat = false;
            };

            # ── Screenshots ───────────────────────────────────────────
            "Print".action.screenshot = [ ];
            "Ctrl+Print".action.screenshot-screen = [ ];
            "Alt+Print".action.screenshot-window = [ ];
            "${hyper}+A".action.screenshot = [ ];

            # ── Monitor focus (Hyper + arrow keys) ────────────────────
            "${hyper}+Left".action.focus-monitor-left = [ ];
            "${hyper}+Right".action.focus-monitor-right = [ ];
            "${hyper}+Up".action.focus-monitor-up = [ ];
            "${hyper}+Down".action.focus-monitor-down = [ ];

            # ── Workspace scroll (Hyper + mouse wheel) ────────────────
            "${hyper}+WheelScrollDown" = {
              action.focus-workspace-down = [ ];
              cooldown-ms = 150;
            };
            "${hyper}+WheelScrollUp" = {
              action.focus-workspace-up = [ ];
              cooldown-ms = 150;
            };
            "${hyper}+WheelScrollRight" = {
              action.focus-column-right = [ ];
              cooldown-ms = 150;
            };
            "${hyper}+WheelScrollLeft" = {
              action.focus-column-left = [ ];
              cooldown-ms = 150;
            };

            # ── Power & Escape ────────────────────────────────────────
            "${hyper}+P".action.power-off-monitors = [ ];
            "${hyper}+Escape" = {
              action.toggle-keyboard-shortcuts-inhibit = [ ];
              allow-inhibiting = false;
            };

            # ── Dynamic Cast ──────────────────────────────────────────
            "${hyper}+D" = {
              action.set-dynamic-cast-window = [ ];
              repeat = false;
            };
            "${meh}+D".action.clear-dynamic-cast-target = [ ];
          };

        # Draw the focus ring around Ghostty rather than as a filled rectangle behind it.
        # This prevents the focus ring color from bleeding through Ghostty's transparent background.
        window-rules = [
          {
            matches = [ { app-id = "^com\\.mitchellh\\.ghostty$"; } ];
            draw-border-with-background = false;
            # Workaround: Ghostty's window-width/window-height config doesn't work
            # on tiling Wayland compositors due to a GTK bootstrap bug.
            # https://github.com/ghostty-org/ghostty/issues/6092
            default-column-width = {
              proportion = 0.5;
            };
          }
          # Indicate screencasted windows with red colors.
          {
            matches = [ { is-window-cast-target = true; } ];
            focus-ring = {
              active = {
                color = "#f38ba8";
              };
              inactive = {
                color = "#7d0d2d";
              };
            };
            border = {
              inactive = {
                color = "#7d0d2d";
              };
            };
            shadow = {
              color = "#7d0d2d70";
            };
          }
        ];
      };
    }
  );
}
