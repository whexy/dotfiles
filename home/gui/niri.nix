# Niri Wayland compositor configuration (Linux)
{
  inputs,
  ...
}:
{
  imports = [
    inputs.niri.homeModules.niri
  ];

  programs.niri.enable = true;

  # Niri settings
  programs.niri.settings = {
    # Skip the hotkey overlay on startup (we have custom binds)
    hotkey-overlay.skip-at-startup = true;

    # Scale all outputs to 150% via IPC (works across machines without
    # knowing output names ahead of time)
    spawn-at-startup = [
      {
        command = [
          "swaybg"
          "--image"
          "${./wallpaper.jpg}"
          "--mode"
          "fill"
        ];
      }
      {
        sh = ''
          sleep 1
          for output in $(niri msg --json outputs | jq -r '.[].name'); do
            niri msg output "$output" scale 1.5
          done
        '';
      }
    ];

    # Transparent workspace background so Ghostty's opacity shows the wallpaper
    layout.background-color = "#00000000";

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
        # Terminal
        "${hyper}+T" = {
          action.spawn = "ghostty";
          repeat = false;
        };

        # Close window
        "${hyper}+Q" = {
          action.close-window = [ ];
          repeat = false;
        };

        # Quit niri (with confirmation dialog)
        "${hyper}+Semicolon" = {
          action.quit = { };
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

        # ── Power & Escape ────────────────────────────────────────
        "${hyper}+P".action.power-off-monitors = [ ];
        "${hyper}+Escape" = {
          action.toggle-keyboard-shortcuts-inhibit = [ ];
          allow-inhibiting = false;
        };
      };

    # Draw the focus ring around Ghostty rather than as a filled rectangle behind it.
    # This prevents the focus ring color from bleeding through Ghostty's transparent background.
    window-rules = [
      {
        matches = [ { app-id = "^com\\.mitchellh\\.ghostty$"; } ];
        draw-border-with-background = false;
      }
    ];
  };
}
