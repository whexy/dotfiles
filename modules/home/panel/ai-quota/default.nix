# AI quota pills for the status bar.
#
# Each selected bar fetches the public quota API and renders current data directly.
# API metadata is shared in ./shared.nix; quota semantics live in ./summary.jq.
{ config, lib, ... }:
{
  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
    ./tmux.nix
  ];

  config =
    lib.mkIf
      (
        config.dotfiles.wm.niri.enable
        && config.dotfiles.panel.waybar.enable
        && config.dotfiles.agents.enable
      )
      {
        programs.niri.settings.window-rules = lib.mkAfter [
          {
            matches = [ { app-id = "^ai-quota-popup$"; } ];
            open-floating = true;
            # Wayland toplevels cannot place themselves; sit above the
            # bottom-left pills instead of niri's centered default.
            default-floating-position = {
              x = 8;
              y = 8;
              relative-to = "bottom-left";
            };
          }
        ];
      };
}
