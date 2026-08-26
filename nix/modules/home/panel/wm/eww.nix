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

  workspacesScript = pkgs.writeShellScript "eww-niri-workspaces" ''
    state="$(${niri} msg --json workspaces 2>/dev/null)" || exit 0
    exec ${jq} -r 'sort_by(.idx)
      | map(if .focused then "[\( .idx)]" else "\( .idx)" end)
      | join(" ")' <<<"$state"
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
        (defpoll WORKSPACES :interval "1s" "${workspacesScript}")
        (defpoll WINDOW_TITLE :interval "1s" "${windowTitleScript}")

        (defwidget workspaces [] (box :class "pill workspaces" (label :text WORKSPACES)))
        (defwidget window-title []
          (box :class "pill window-title" (label :text WINDOW_TITLE :limit-width 50)))
      '';

      left = lib.mkMerge [
        (lib.mkBefore [ "workspaces" ])
        (lib.mkAfter [ "window-title" ])
      ];
    };
  };
}
