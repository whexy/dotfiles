# Renpho weight pill for Waybar (Linux).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;

  jq = lib.getExe pkgs.jq;
  icon = "󰓅";

  enabled = cfg.renpho.enable && cfg.renderer == "waybar";

  weightScript = import ./weight.nix { inherit config lib pkgs; };

  pillScript = pkgs.writeShellScript "waybar-renpho" ''
    weight="$(${weightScript})"
    stale=$?
    if [ -z "$weight" ]; then
      exec ${jq} -cn --arg icon '${icon}' '{text: ($icon + " …"), class: "stale"}'
    fi
    exec ${jq} -cn --arg icon '${icon}' --arg weight "$weight" --argjson stale "$stale" \
      '{text: ($icon + " " + $weight + "kg")} + (if $stale == 1 then {class: "stale"} else {} end)'
  '';
in
{
  config = lib.mkIf enabled {
    programs.waybar.settings.mainBar = {
      "modules-right" = lib.mkAfter [ "custom/renpho" ];

      "custom/renpho" = {
        exec = pillScript;
        interval = 300;
        return-type = "json";
      };
    };

    programs.waybar.style = lib.mkAfter ''
      #custom-renpho {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        background-color: #3c3836;
        color: #d3869b;
        transition: all 0.3s ease;
      }

      #custom-renpho.stale { color: #928374; }

      #custom-renpho:hover {
        background-color: #d3869b;
        color: #282828;
      }
    '';
  };
}
