# Renpho weight widget for Eww (Linux).
#
# One Eww poll runs the shared ./weight.nix script; the 300s tick reads its
# cache until the server's next check time.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;

  icon = "󰓅";

  enabled = cfg.renpho.enable && cfg.renderer == "eww";

  weightScript = import ./weight.nix { inherit config lib pkgs; };
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (defpoll RENPHO :interval "300s"
          :initial ""
          "${weightScript}")

        (defwidget renpho []
          (box :class "pill renpho"
            (label :text {"${icon} " + (RENPHO == "" ? "…" : RENPHO + "kg")})))
      '';

      right = lib.mkAfter [ "renpho" ];

      styles = ''
        .renpho {
          color: #efb876;
        }
      '';
    };
  };
}
