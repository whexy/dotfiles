# Waybar window-manager modules (Linux, niri). The Eww counterpart lives
# in ./eww.nix; both are selected by dotfiles.panel.linuxBar.
#
# Contributes niri/workspaces and niri/window around the core bar's
# idle_inhibitor in modules-left: mkBefore lands workspaces before it and
# mkAfter lands the window title after it, preserving the original layout.
# Settings and style merge in with mkAfter, so ../waybar.nix stays
# WM-agnostic.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;
  inherit (import ../../desktop/style.nix) colors;
  niri = lib.getExe config.programs.niri.package;
  sshWindow = lib.getExe config.programs.ssh-window.package;
  niriEvents = import ./niri-events.nix { inherit lib pkgs niri; };
  windowTitles = import ./window-titles.nix;

  enabled = cfg.renderer == "waybar" && config.dotfiles.wm.niri.enable;
in
{
  config = lib.mkIf enabled {
    programs.waybar.settings.mainBar = lib.mkMerge [
      {
        "modules-left" = lib.mkBefore [ "niri/workspaces" ];
        "niri/workspaces" = {
          format = "{index}";
        };
      }
      {
        "modules-left" = lib.mkAfter (
          [ "niri/window" ] ++ lib.optional config.programs.ssh-window.enable "custom/ssh-context"
        );
        "niri/window" = {
          format = "{}";
          max-length = 50;
          rewrite =
            lib.listToAttrs (
              map (t: lib.nameValuePair "(.*)${lib.escapeRegex t.suffix}" "${t.icon} $1") windowTitles
            )
            // {
              "(.*)" = "$1";
            };
        };
      }
      (lib.mkIf config.programs.ssh-window.enable {
        # Without an interval Waybar keeps the listener running and shows
        # each line it prints.
        "custom/ssh-context" = {
          exec = "${niriEvents.sshContext sshWindow}";
          format = "󰣀 {text}";
          hide-empty-text = true;
          escape = true;
          max-length = 40;
          tooltip-format = "SSH context: {text}";
        };
      })
    ];

    programs.waybar.style = lib.mkAfter ''
      /* Workspaces */
      #workspaces {
        padding: 0;
        background-color: transparent;
      }

      #workspaces button {
        padding: 2px 8px;
        margin: 3px 1px;
        border-radius: 10px;
        color: ${colors.gray};
        background-color: ${colors.bg1};
        border: none;
        transition: all 0.3s ease;
      }

      #workspaces button:hover {
        background-color: ${colors.bg2};
        color: ${colors.fg};
      }

      #workspaces button.active {
        color: ${colors.bg0};
        background-color: ${colors.blue};
        font-weight: bold;
      }

      /* Window title */
      #window {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        background-color: ${colors.bg1};
        transition: all 0.3s ease;
        color: ${colors.fg4};
        font-style: italic;
      }

      #custom-ssh-context {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        color: ${colors.greenBright};
        background-color: rgba(184, 187, 38, 0.14);
        border: 1px solid rgba(184, 187, 38, 0.5);
        font-style: normal;
      }
    '';
  };
}
