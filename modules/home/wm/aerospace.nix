# Aerospace window manager configuration (macOS)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.wm;
  shared = import ./shared.nix { inherit config pkgs; };
  hyper = shared.hyper.aerospace;
  meh = shared.meh.aerospace;
  inherit (config.dotfiles.panel.sketchybar) reserve;
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
            inherit (reserve) top bottom;
          };
        };

        mode.main.binding = {
          "${hyper}-s" = "layout tiles accordion";
          "${hyper}-h" = "focus left --boundaries all-monitors-outer-frame";
          "${hyper}-j" = "focus down --boundaries all-monitors-outer-frame";
          "${hyper}-k" = "focus up --boundaries all-monitors-outer-frame";
          "${hyper}-l" = "focus right --boundaries all-monitors-outer-frame";
          "${hyper}-tab" = "focus-back-and-forth";
          "${meh}-h" = "move left";
          "${meh}-j" = "move down";
          "${meh}-k" = "move up";
          "${meh}-l" = "move right";
          "${meh}-f" = "fullscreen";
          "${meh}-minus" = "resize smart -50";
          "${meh}-equal" = "resize smart +50";
          "${hyper}-1" = "workspace 1";
          "${hyper}-2" = "workspace 2";
          "${hyper}-3" = "workspace 3";
          "${hyper}-4" = "workspace 4";
          "${hyper}-5" = "workspace 5";
          "${hyper}-6" = "workspace 6";
          "${hyper}-7" = "workspace 7";
          "${hyper}-8" = "workspace 8";
          "${hyper}-9" = "workspace 9";
          "${hyper}-0" = "workspace 10";
          "${meh}-1" = "move-node-to-workspace 1 --focus-follows-window";
          "${meh}-2" = "move-node-to-workspace 2 --focus-follows-window";
          "${meh}-3" = "move-node-to-workspace 3 --focus-follows-window";
          "${meh}-4" = "move-node-to-workspace 4 --focus-follows-window";
          "${meh}-5" = "move-node-to-workspace 5 --focus-follows-window";
          "${meh}-6" = "move-node-to-workspace 6 --focus-follows-window";
          "${meh}-7" = "move-node-to-workspace 7 --focus-follows-window";
          "${meh}-8" = "move-node-to-workspace 8 --focus-follows-window";
          "${meh}-9" = "move-node-to-workspace 9 --focus-follows-window";
          "${meh}-0" = "move-node-to-workspace 10 --focus-follows-window";
          "${meh}-leftSquareBracket" = "join-with left";
          "${meh}-rightSquareBracket" = "join-with right";
          "${meh}-left" = "move-node-to-monitor --wrap-around prev";
          "${meh}-right" = "move-node-to-monitor --wrap-around next";
          "${hyper}-f" = "layout floating tiling";
          "${hyper}-left" = "focus-monitor --wrap-around prev";
          "${hyper}-right" = "focus-monitor --wrap-around next";
          "${hyper}-t" =
            {
              rex = "exec-and-forget open -a 'Rex Beta'";
              ssh-window = "exec-and-forget ${config.programs.ssh-window.package}/bin/ssh-window launch";
              ghostty = "exec-and-forget open -a Ghostty";
            }
            .${shared.terminal};
          "${hyper}-q" = "close";
        }
        // lib.optionalAttrs shared.t3codeDesktop {
          "${meh}-t" = "exec-and-forget open -a 'T3 Code (Nightly)'";
        }
        // {
          # service binding
          "${hyper}-semicolon" = "mode service";
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
          "${meh}-h" = [
            "join-with left"
            "mode main"
          ];
          "${meh}-j" = [
            "join-with down"
            "mode main"
          ];
          "${meh}-k" = [
            "join-with up"
            "mode main"
          ];
          "${meh}-l" = [
            "join-with right"
            "mode main"
          ];
        };
      };
    };
  };
}
