# Aerospace window manager configuration (macOS)
{ pkgs, ... }:
{
  programs.aerospace = {
    enable = true;
    package = pkgs.unstable.aerospace;

    userSettings = {
      config-version = 2;
      after-startup-command = [ ];
      start-at-login = true;
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      accordion-padding = 30;
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      on-focus-changed = [ "move-mouse window-lazy-center" ];
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

      key-mapping.preset = "qwerty";

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

      mode.main.binding = {
        cmd-alt-ctrl-slash = "layout tiles horizontal vertical";
        cmd-alt-ctrl-comma = "layout accordion horizontal vertical";
        cmd-alt-ctrl-shift-h = "focus left --boundaries all-monitors-outer-frame";
        cmd-alt-ctrl-shift-j = "focus down --boundaries all-monitors-outer-frame";
        cmd-alt-ctrl-shift-k = "focus up --boundaries all-monitors-outer-frame";
        cmd-alt-ctrl-shift-l = "focus right --boundaries all-monitors-outer-frame";
        cmd-alt-ctrl-shift-tab = "focus-back-and-forth";
        cmd-alt-ctrl-h = "move left";
        cmd-alt-ctrl-j = "move down";
        cmd-alt-ctrl-k = "move up";
        cmd-alt-ctrl-l = "move right";
        cmd-alt-ctrl-f = "fullscreen";
        cmd-alt-ctrl-minus = "resize smart -50";
        cmd-alt-ctrl-equal = "resize smart +50";
        cmd-alt-ctrl-shift-1 = "workspace 1";
        cmd-alt-ctrl-shift-2 = "workspace 2";
        cmd-alt-ctrl-shift-3 = "workspace 3";
        cmd-alt-ctrl-shift-4 = "workspace 4";
        cmd-alt-ctrl-shift-5 = "workspace 5";
        cmd-alt-ctrl-shift-6 = "workspace 6";
        cmd-alt-ctrl-shift-7 = "workspace 7";
        cmd-alt-ctrl-shift-8 = "workspace 8";
        cmd-alt-ctrl-shift-9 = "workspace 9";
        cmd-alt-ctrl-shift-0 = "workspace 10";
        cmd-alt-ctrl-1 = "move-node-to-workspace 1";
        cmd-alt-ctrl-2 = "move-node-to-workspace 2";
        cmd-alt-ctrl-3 = "move-node-to-workspace 3";
        cmd-alt-ctrl-4 = "move-node-to-workspace 4";
        cmd-alt-ctrl-5 = "move-node-to-workspace 5";
        cmd-alt-ctrl-6 = "move-node-to-workspace 6";
        cmd-alt-ctrl-7 = "move-node-to-workspace 7";
        cmd-alt-ctrl-8 = "move-node-to-workspace 8";
        cmd-alt-ctrl-9 = "move-node-to-workspace 9";
        cmd-alt-ctrl-0 = "move-node-to-workspace 10";
        cmd-alt-ctrl-left = "move-workspace-to-monitor --wrap-around prev";
        cmd-alt-ctrl-right = "move-workspace-to-monitor --wrap-around next";
        cmd-alt-ctrl-shift-semicolon = "mode service";
      };

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
}
