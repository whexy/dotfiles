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
  sshWindow = lib.getExe config.programs.ssh-window.package;
  niriEvents = import ./niri-events.nix { inherit lib pkgs niri; };

  enabled = cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin);

  # One JSON record per workspace so the widget can render per-workspace
  # buttons with focused/occupied/empty states (niri's fields are
  # is_focused/active_window_id).
  workspacesScript = niriEvents.listen "eww-niri-workspaces" "-c" ''
    .workspaces | [sort_by(.idx)[]
      | {
          idx: (.idx | tostring),
          focused: .is_focused,
          occupied: (.active_window_id != null)
        }]
  '';

  # Same title rewrites as the Waybar module.
  windowTitleScript = niriEvents.listen "eww-niri-window-title" "-r" ''
    focused_window | .title // ""
    | if endswith(" — Mozilla Firefox") then "󰈹 " + rtrimstr(" — Mozilla Firefox")
      elif endswith(" - fish") then " " + rtrimstr(" - fish")
      else . end
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (deflisten WORKSPACES :initial "[]" "${workspacesScript}")
        (deflisten WINDOW_TITLE "${windowTitleScript}")
        ${lib.optionalString config.dotfiles.ssh.windowMultiplexing.enable ''
          (deflisten SSH_CONTEXT :initial "" "${niriEvents.sshContext sshWindow}")
        ''}

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
        ${lib.optionalString config.dotfiles.ssh.windowMultiplexing.enable ''
          (defwidget ssh-context []
            (box :class "pill ssh-context" :visible {SSH_CONTEXT != ""}
              (label :text {"󰣀 " + SSH_CONTEXT} :limit-width 40)))
        ''}
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

        .ssh-context {
          color: #b1d18b;
          background-color: rgba(177, 209, 139, 0.14);
          border: 1px solid rgba(177, 209, 139, 0.5);
        }
      '';

      left = lib.mkMerge [
        (lib.mkBefore [ "workspaces" ])
        (lib.mkAfter (
          [ "window-title" ] ++ lib.optional config.dotfiles.ssh.windowMultiplexing.enable "ssh-context"
        ))
      ];
    };
  };
}
