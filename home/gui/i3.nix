# i3 window manager configuration (Linux/WSL)
# Runs in Xephyr nested X server for WSLg compatibility
{
  pkgs,
  lib,
  darwin,
  ...
}:
let
  # Use Alt as main modifier since Windows captures Super/Win key in WSLg
  mod = "Mod1"; # Alt key

  # Script to launch i3 in Xephyr
  i3-xephyr = pkgs.writeShellScriptBin "i3-xephyr" ''
    # Default resolution, can be overridden with arguments
    RESOLUTION="''${1:-1920x1080}"
    DISPLAY_NUM="''${2:-1}"

    # Kill any existing Xephyr on this display
    ${pkgs.killall}/bin/killall -q Xephyr 2>/dev/null || true
    sleep 0.2

    # Start Xephyr
    ${pkgs.xorg.xorgserver}/bin/Xephyr ":$DISPLAY_NUM" \
      -screen "$RESOLUTION" \
      -resizeable \
      -title "i3 (Xephyr)" \
      -ac &

    XEPHYR_PID=$!
    sleep 0.5

    # Start i3 in the nested display
    DISPLAY=":$DISPLAY_NUM" ${pkgs.i3}/bin/i3 &

    # Wait for Xephyr to exit
    wait $XEPHYR_PID
  '';
in
lib.mkIf (!darwin) {
  home.packages = [
    pkgs.xorg.xorgserver # Xephyr
    i3-xephyr
  ];
  xsession.windowManager.i3 = {
    enable = true;
    package = pkgs.i3;

    config = {
      modifier = mod;

      # No window decorations, similar to aerospace
      window = {
        titlebar = false;
        border = 1;
      };

      # No gaps, matching aerospace config
      gaps = {
        inner = 0;
        outer = 0;
      };

      # Default layout
      defaultWorkspace = "workspace number 1";

      # Keybindings - Alt-based for WSLg compatibility
      # (Windows captures Super key, so we use Alt as primary modifier)
      keybindings = lib.mkOptionDefault {
        # Layout switching
        "${mod}+slash" = "layout toggle split";
        "${mod}+comma" = "layout stacking tabbed";

        # Focus movement (Alt+Shift+hjkl)
        "${mod}+Shift+h" = "focus left";
        "${mod}+Shift+j" = "focus down";
        "${mod}+Shift+k" = "focus up";
        "${mod}+Shift+l" = "focus right";

        # Focus back and forth
        "${mod}+Tab" = "workspace back_and_forth";

        # Window movement (Alt+Ctrl+hjkl)
        "${mod}+Control+h" = "move left";
        "${mod}+Control+j" = "move down";
        "${mod}+Control+k" = "move up";
        "${mod}+Control+l" = "move right";

        # Fullscreen
        "${mod}+f" = "fullscreen toggle";

        # Resize
        "${mod}+minus" = "resize shrink width 50 px or 5 ppt";
        "${mod}+equal" = "resize grow width 50 px or 5 ppt";

        # Workspace switching (Alt+1-9)
        "${mod}+1" = "workspace number 1";
        "${mod}+2" = "workspace number 2";
        "${mod}+3" = "workspace number 3";
        "${mod}+4" = "workspace number 4";
        "${mod}+5" = "workspace number 5";
        "${mod}+6" = "workspace number 6";
        "${mod}+7" = "workspace number 7";
        "${mod}+8" = "workspace number 8";
        "${mod}+9" = "workspace number 9";

        # Move window to workspace (Alt+Shift+1-9)
        "${mod}+Shift+1" = "move container to workspace number 1";
        "${mod}+Shift+2" = "move container to workspace number 2";
        "${mod}+Shift+3" = "move container to workspace number 3";
        "${mod}+Shift+4" = "move container to workspace number 4";
        "${mod}+Shift+5" = "move container to workspace number 5";
        "${mod}+Shift+6" = "move container to workspace number 6";
        "${mod}+Shift+7" = "move container to workspace number 7";
        "${mod}+Shift+8" = "move container to workspace number 8";
        "${mod}+Shift+9" = "move container to workspace number 9";

        # Move workspace to monitor
        "${mod}+Control+Left" = "move workspace to output left";
        "${mod}+Control+Right" = "move workspace to output right";

        # Service mode
        "${mod}+semicolon" = "mode \"service\"";

        # Terminal launcher - force X11 backend for ghostty in Xephyr
        "${mod}+Return" = "exec --no-startup-id env GDK_BACKEND=x11 ${pkgs.ghostty}/bin/ghostty";

        # Kill window
        "${mod}+Shift+q" = "kill";

        # Reload config
        "${mod}+Shift+c" = "reload";

        # Restart i3
        "${mod}+Shift+r" = "restart";

        # Exit i3
        "${mod}+Shift+e" = "exec i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'";

        # Toggle floating
        "${mod}+Shift+space" = "floating toggle";

        # Focus floating/tiling
        "${mod}+space" = "focus mode_toggle";

        # Split orientation
        "${mod}+b" = "split h";
        "${mod}+v" = "split v";
      };

      # Service mode (similar to aerospace service mode)
      modes = {
        service = {
          # Escape to reload and exit mode
          "Escape" = "reload, mode default";

          # Flatten (reset splits) - closest equivalent
          "r" = "layout default, mode default";

          # Toggle floating
          "f" = "floating toggle, mode default";

          # Close all but current - i3 doesn't have this natively
          # Using a script workaround
          "BackSpace" =
            "exec --no-startup-id i3-msg '[workspace=__focused__ class=.*] kill' && i3-msg 'mode default'";

          # Join with direction (move to parent and merge)
          "${mod}+h" = "move left, mode default";
          "${mod}+j" = "move down, mode default";
          "${mod}+k" = "move up, mode default";
          "${mod}+l" = "move right, mode default";
        };
      };

      # i3bar configuration
      bars = [
        {
          position = "bottom";
          statusCommand = "${pkgs.i3status}/bin/i3status";
          colors = {
            background = "#282828";
            statusline = "#ebdbb2";
            separator = "#666666";
            focusedWorkspace = {
              border = "#458588";
              background = "#458588";
              text = "#ebdbb2";
            };
            activeWorkspace = {
              border = "#83a598";
              background = "#83a598";
              text = "#282828";
            };
            inactiveWorkspace = {
              border = "#282828";
              background = "#282828";
              text = "#928374";
            };
            urgentWorkspace = {
              border = "#cc241d";
              background = "#cc241d";
              text = "#ebdbb2";
            };
          };
        }
      ];

      # Gruvbox colors for window borders
      colors = {
        focused = {
          border = "#458588";
          background = "#458588";
          text = "#ebdbb2";
          indicator = "#83a598";
          childBorder = "#458588";
        };
        focusedInactive = {
          border = "#282828";
          background = "#282828";
          text = "#928374";
          indicator = "#282828";
          childBorder = "#282828";
        };
        unfocused = {
          border = "#282828";
          background = "#282828";
          text = "#928374";
          indicator = "#282828";
          childBorder = "#282828";
        };
        urgent = {
          border = "#cc241d";
          background = "#cc241d";
          text = "#ebdbb2";
          indicator = "#cc241d";
          childBorder = "#cc241d";
        };
      };

      # Startup applications
      startup = [
        # Set wallpaper if feh is available
        {
          command = "${pkgs.feh}/bin/feh --bg-fill ~/.wallpaper.png 2>/dev/null || true";
          notification = false;
        }
      ];
    };
  };

  # i3status configuration
  programs.i3status = {
    enable = true;
    general = {
      colors = true;
      color_good = "#b8bb26";
      color_degraded = "#fabd2f";
      color_bad = "#fb4934";
      interval = 5;
    };
    modules = {
      ipv6.enable = false;
      "wireless _first_".enable = false;
      "battery all".enable = false;
      "tztime local" = {
        position = 1;
        settings = {
          format = "%Y-%m-%d %H:%M:%S";
        };
      };
      "load" = {
        position = 2;
        settings = {
          format = "load: %1min";
        };
      };
      "memory" = {
        position = 3;
        settings = {
          format = "mem: %used / %total";
          threshold_degraded = "10%";
          threshold_critical = "5%";
        };
      };
      "disk /" = {
        position = 4;
        settings = {
          format = "disk: %avail";
        };
      };
    };
  };
}
