# Renpho weight pill for Waybar (Linux).
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  hcfg = config.services.renpho-health;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;
  icon = "󰓅";
  summaryCount = 5;
  staleAfter = 36 * 60 * 60;

  enabled = cfg.renpho.enable && cfg.waybar.enable && (!isDarwin);

  pillScript = pkgs.writeShellScript "waybar-renpho" ''
    cache=${lib.escapeShellArg hcfg.cachePath}
    now="$(${pkgs.coreutils}/bin/date +%s)"

    if [ ! -f "$cache" ]; then
      exec ${jq} -cn --arg icon '${icon}' '{ text: ($icon + " …"), tooltip: "no data yet", class: "stale" }'
    fi

    summary="$(${jq} -c --argjson summary_count ${toString summaryCount} -f ${summaryFilter} "$cache" 2>/dev/null)" ||
      exec ${jq} -cn --arg icon '${icon}' '{ text: ($icon + " …"), tooltip: "cache unreadable", class: "stale" }'

    modified="$(${pkgs.coreutils}/bin/stat -c %Y "$cache" 2>/dev/null || printf 0)"
    age=$((now - modified))

    exec ${jq} -cn \
      --argjson summary "$summary" \
      --arg icon '${icon}' \
      --argjson age "$age" \
      --argjson stale_after ${toString staleAfter} '
        def rounded: (. * 10 | round / 10 | tostring);
        if $summary.present == false then
          { text: ($icon + " …"), tooltip: ($summary.lines | join("\n")), class: "stale" }
        else
          ($age > $stale_after) as $stale
          | {
              text: ($icon + " "
                + (if ($summary.weight | type) == "number" then ($summary.weight | rounded) + "kg" else "?" end)
                + (if $summary.trend == "" then "" elif $summary.delta == null then " " + $summary.trend else " " + $summary.trend + ($summary.delta | tostring) end)),
              tooltip: ((if $stale then "[cache " + (($age / 3600) | floor | tostring) + "h old]\n" else "" end)
                + ($summary.lines | join("\n"))),
              class: (if $stale then "stale" else $summary.state end)
            }
        end'
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
        escape = false;
        format = "{}";
        tooltip = true;
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

      #custom-renpho.down { color: #b8bb26; }
      #custom-renpho.up { color: #fb4934; }
      #custom-renpho.stale { color: #928374; }

      #custom-renpho:hover {
        background-color: #d3869b;
        color: #282828;
      }
    '';
  };
}
