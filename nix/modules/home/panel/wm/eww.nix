# Eww window-manager widgets (Linux, niri).
#
# Eww counterpart of ./waybar.nix: contributes workspace and focused-window
# widgets through the extension points in ../eww.nix (defs, left slot).
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  niri = lib.getExe config.programs.niri.package;
  jq = lib.getExe pkgs.jq;

  enabled = cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin);

  # One JSON record per workspace so the widget can render per-workspace
  # buttons with focused/occupied/empty states (niri's fields are
  # is_focused/active_window_id).
  workspacesScript = pkgs.writeShellScript "eww-niri-workspaces" ''
    state="$(${niri} msg --json workspaces 2>/dev/null)" || exit 0
    exec ${jq} -c '[sort_by(.idx)[]
      | {
          idx: (.idx | tostring),
          focused: .is_focused,
          occupied: (.active_window_id != null)
        }]' <<<"$state"
  '';

  # Same title rewrites as the Waybar module.
  windowTitleScript = pkgs.writeShellScript "eww-niri-window-title" ''
    title="$(${niri} msg --json focused-window 2>/dev/null | ${jq} -r '.title // empty')" || exit 0
    case "$title" in
      *" — Mozilla Firefox") title="󰈹 ''${title%" — Mozilla Firefox"}" ;;
      *" - fish") title=" ''${title%" - fish"}" ;;
    esac
    printf '%s' "$title"
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (defpoll WORKSPACES :interval "1s" :initial "[]" "${workspacesScript}")
        (defpoll WINDOW_TITLE :interval "1s" "${windowTitleScript}")

        ; One button per workspace so the focused one can be highlighted and
        ; empty ones dimmed (the paneru SketchyBar states); clicks switch.
        (defwidget workspaces []
          (box :class "pill workspaces" :spacing 2 :visible {jq(WORKSPACES, "length") > 0}
            (for ws in {WORKSPACES}
              (button
                :class {"ws" + (ws.focused ? " focused" : (ws.occupied ? " occupied" : " empty"))}
                :onclick {"${niri} msg action focus-workspace " + ws.idx}
                (label :text {ws.idx})))))
        (defwidget window-title []
          (box :class "pill window-title" (label :text WINDOW_TITLE :limit-width 50)))
      '';

      styles = ''
        // Focused = filled primary pill, occupied = full emphasis, empty =
        // dimmed; mirrors the paneru SketchyBar workspace states.
        .workspaces {
          padding: 2px 5px;
        }

        .workspaces .ws {
          border-radius: 10px;
          padding: 0 8px;
          color: $on-surface-dim;
        }

        .workspaces .ws.occupied {
          color: $on-surface;
        }

        .workspaces .ws.focused {
          background-color: $primary;
          color: $on-primary;
          font-weight: bold;
        }

        .workspaces .ws:hover {
          background-color: $surface-container-highest;
        }

        .workspaces .ws.focused:hover {
          background-color: $primary;
        }

        // Dimmed secondary readout, like SketchyBar's front app.
        .window-title {
          color: $on-surface-variant;
        }
      '';

      left = lib.mkMerge [
        (lib.mkBefore [ "workspaces" ])
        (lib.mkAfter [ "window-title" ])
      ];
    };
  };
}
