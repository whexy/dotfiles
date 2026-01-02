{
  home-manager.users.whexy =
    { pkgs, ... }:
    {
      programs.aerospace = {
        enable = true;
        package = pkgs.unstable.aerospace;

        userSettings = {
          # You can use it to add commands that run after AeroSpace startup.
          after-startup-command = [ ];

          # Start AeroSpace at login
          start-at-login = true;

          # Normalizations
          enable-normalization-flatten-containers = true;
          enable-normalization-opposite-orientation-for-nested-containers = true;

          # Layouts
          accordion-padding = 30;
          default-root-container-layout = "tiles";
          default-root-container-orientation = "auto";

          # Mouse follows focus when focused monitor changes
          on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

          # Disable macOS "Hide application" feature
          automatically-unhide-macos-hidden-apps = false;

          persistent-workspaces = [
            "1"
            "2"
            "3"
            "4"
            "5"
            "6"
            "7"
            "8"
            "9"
          ];

          # Workspace to monitor assignments
          workspace-to-monitor-force-assignment = {
            "8" = [
              1
              "main"
            ];
            "9" = [
              3
              "main"
            ];
          };

          # Key mapping
          key-mapping = {
            preset = "qwerty";
          };

          # Gaps between windows
          gaps = {
            inner = {
              horizontal = 0;
              vertical = 0;
            };
            outer = {
              left = 0;
              bottom = 0;
              top = 0;
              right = 0;
            };
          };

          # Main binding mode
          mode.main.binding = {
            # Layout commands
            cmd-alt-ctrl-slash = "layout tiles horizontal vertical";
            cmd-alt-ctrl-comma = "layout accordion horizontal vertical";

            # Focus commands
            cmd-alt-ctrl-shift-h = "focus left";
            cmd-alt-ctrl-shift-j = "focus down";
            cmd-alt-ctrl-shift-k = "focus up";
            cmd-alt-ctrl-shift-l = "focus right";
            cmd-alt-ctrl-shift-tab = "focus-back-and-forth";

            # Move commands
            cmd-alt-ctrl-h = "move left";
            cmd-alt-ctrl-j = "move down";
            cmd-alt-ctrl-k = "move up";
            cmd-alt-ctrl-l = "move right";
            cmd-alt-ctrl-f = "fullscreen";

            # Resize commands
            cmd-alt-ctrl-minus = "resize smart -50";
            cmd-alt-ctrl-equal = "resize smart +50";

            # Workspace commands
            cmd-alt-ctrl-shift-1 = "workspace 1";
            cmd-alt-ctrl-shift-2 = "workspace 2";
            cmd-alt-ctrl-shift-3 = "workspace 3";
            cmd-alt-ctrl-shift-4 = "workspace 4";
            cmd-alt-ctrl-shift-5 = "workspace 5";
            cmd-alt-ctrl-shift-6 = "workspace 6";
            cmd-alt-ctrl-shift-7 = "workspace 7";
            cmd-alt-ctrl-shift-8 = "workspace 8";
            cmd-alt-ctrl-shift-9 = "workspace 9";

            # Move node to workspace commands
            cmd-alt-ctrl-1 = "move-node-to-workspace 1";
            cmd-alt-ctrl-2 = "move-node-to-workspace 2";
            cmd-alt-ctrl-3 = "move-node-to-workspace 3";
            cmd-alt-ctrl-4 = "move-node-to-workspace 4";
            cmd-alt-ctrl-5 = "move-node-to-workspace 5";
            cmd-alt-ctrl-6 = "move-node-to-workspace 6";
            cmd-alt-ctrl-7 = "move-node-to-workspace 7";
            cmd-alt-ctrl-8 = "move-node-to-workspace 8";
            cmd-alt-ctrl-9 = "move-node-to-workspace 9";

            # Move workspace to monitor
            cmd-alt-ctrl-left = "move-workspace-to-monitor --wrap-around prev";
            cmd-alt-ctrl-right = "move-workspace-to-monitor --wrap-around next";

            # Mode switching
            cmd-alt-ctrl-shift-semicolon = "mode service";
          };

          # Service binding mode
          mode.service.binding = {
            esc = [
              "reload-config"
              "mode main"
            ];
            r = [
              "flatten-workspace-tree"
              "mode main"
            ];
            f = [
              "layout floating tiling"
              "mode main"
            ];
            backspace = [
              "close-all-windows-but-current"
              "mode main"
            ];
            cmd-alt-ctrl-h = [
              "join-with left"
              "mode main"
            ];
            cmd-alt-ctrl-j = [
              "join-with down"
              "mode main"
            ];
            cmd-alt-ctrl-k = [
              "join-with up"
              "mode main"
            ];
            cmd-alt-ctrl-l = [
              "join-with right"
              "mode main"
            ];
          };
        };
      };
    };
}
