# Waybar window-manager modules (Linux, niri). The Eww counterpart lives
# in ../eww.nix; both are selected by dotfiles.panel.linuxBar.
#
# Contributes niri/workspaces and niri/window around the core bar's
# idle_inhibitor in modules-left: mkBefore lands workspaces before it and
# mkAfter lands the window title after it, preserving the original layout.
# Settings and style merge in with mkAfter, so ../waybar.nix stays
# WM-agnostic.
args@{
  config,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  enabled = cfg.waybar.enable && cfg.linuxBar == "waybar" && (!isDarwin);
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
        "modules-left" = lib.mkAfter [ "niri/window" ];
        "niri/window" = {
          format = "{}";
          max-length = 50;
          rewrite = {
            "(.*) — Mozilla Firefox" = "󰈹 $1";
            "(.*) - fish" = " $1";
            "(.*)" = "$1";
          };
        };
      }
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
        color: #928374;
        background-color: #3c3836;
        border: none;
        transition: all 0.3s ease;
      }

      #workspaces button:hover {
        background-color: #504945;
        color: #ebdbb2;
      }

      #workspaces button.active {
        color: #282828;
        background-color: #458588;
        font-weight: bold;
      }

      /* Window title */
      #window {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        background-color: #3c3836;
        transition: all 0.3s ease;
        color: #a89984;
        font-style: italic;
      }
    '';
  };
}
