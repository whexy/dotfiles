# AI quota pills for the status bar.
#
# Each selected bar fetches the public quota API and renders current data directly.
# API and provider metadata and the quota semantics (summary.jq) come from
# the ai-quota-popup package, which renders the same data in detail.
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
        && lib.elem config.dotfiles.panel.renderer [
          "waybar"
          "eww"
        ]
        && config.dotfiles.panel.aiQuota.enable
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
