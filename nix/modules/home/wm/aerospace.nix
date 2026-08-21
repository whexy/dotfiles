# Aerospace window manager configuration (macOS)
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.wm;
  osConfig = args.osConfig or null;
  autoHideMenuBar = osConfig != null && (osConfig.dotfiles.hardware.display.autoHideMenuBar or true);
  sketchybar = lib.getExe pkgs.sketchybar;
in
{
  config = lib.mkIf (cfg.darwin.enable && cfg.darwin.windowManager == "aerospace") {
    programs.aerospace = {
      enable = true;
      package = pkgs.unstable.aerospace;

      # Let Home Manager manage Aerospace's launchd agent. Required by HM
      # 26.05 when `start-at-login = true` is set in userSettings, otherwise
      # an assertion fails to avoid conflicting startup mechanisms.
      launchd.enable = true;

      settings = {
        config-version = 2;
        after-startup-command = [ ];
        exec-on-workspace-change = lib.optionals config.dotfiles.panel.sketchybar.enable [
          "/bin/bash"
          "-c"
          "${sketchybar} --trigger wm_state_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"
        ];
        start-at-login = true;
        enable-normalization-flatten-containers = true;
        enable-normalization-opposite-orientation-for-nested-containers = true;
        accordion-padding = 30;
        default-root-container-layout = "tiles";
        default-root-container-orientation = "auto";
        on-focus-changed = [
          "move-mouse window-lazy-center"
        ]
        ++ lib.optional config.dotfiles.panel.sketchybar.enable "exec-and-forget ${sketchybar} --trigger wm_state_change";
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
            right = 0;
            top = if (config.dotfiles.panel.sketchybar.enable && autoHideMenuBar) then 34 else 0;
            bottom = if (config.dotfiles.panel.sketchybar.enable && !autoHideMenuBar) then 34 else 0;
          };
        };

        mode.main.binding = {
          cmd-alt-ctrl-shift-s = "layout tiles accordion";
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
          cmd-alt-ctrl-1 = "move-node-to-workspace 1 --focus-follows-window";
          cmd-alt-ctrl-2 = "move-node-to-workspace 2 --focus-follows-window";
          cmd-alt-ctrl-3 = "move-node-to-workspace 3 --focus-follows-window";
          cmd-alt-ctrl-4 = "move-node-to-workspace 4 --focus-follows-window";
          cmd-alt-ctrl-5 = "move-node-to-workspace 5 --focus-follows-window";
          cmd-alt-ctrl-6 = "move-node-to-workspace 6 --focus-follows-window";
          cmd-alt-ctrl-7 = "move-node-to-workspace 7 --focus-follows-window";
          cmd-alt-ctrl-8 = "move-node-to-workspace 8 --focus-follows-window";
          cmd-alt-ctrl-9 = "move-node-to-workspace 9 --focus-follows-window";
          cmd-alt-ctrl-0 = "move-node-to-workspace 10 --focus-follows-window";
          cmd-alt-ctrl-leftSquareBracket = "join-with left";
          cmd-alt-ctrl-rightSquareBracket = "join-with right";
          cmd-alt-ctrl-left = "move-node-to-monitor --wrap-around prev";
          cmd-alt-ctrl-right = "move-node-to-monitor --wrap-around next";
          cmd-alt-ctrl-shift-f = "layout floating tiling";
          cmd-alt-ctrl-shift-left = "focus-monitor --wrap-around prev";
          cmd-alt-ctrl-shift-right = "focus-monitor --wrap-around next";
          cmd-alt-ctrl-shift-t = "exec-and-forget open -a Ghostty";
          cmd-alt-ctrl-shift-q = "close";

          # service binding
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
