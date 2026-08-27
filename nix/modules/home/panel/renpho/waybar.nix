# Renpho weight pill for Waybar (Linux).
args@{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  renphoHealth = lib.getExe inputs.renpho-health.packages.${pkgs.stdenv.hostPlatform.system}.default;
  credsFile = config.age.secrets.renpho-creds.path;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;
  icon = "󰓅";
  summaryCount = 5;

  enabled = cfg.renpho.enable && cfg.waybar.enable && cfg.linuxBar == "waybar" && (!isDarwin);

  pillScript = pkgs.writeShellScript "waybar-renpho" ''
    raw="$(${renphoHealth} recent --count ${toString summaryCount} --creds-file "${credsFile}" 2>/dev/null)" ||
      exec ${jq} -cn --arg icon '${icon}' '{text: ($icon + " …"), tooltip: "fetch failed", class: "stale"}'
    summary="$(printf '%s\n' "$raw" | ${jq} -c --argjson summary_count ${toString summaryCount} -f ${summaryFilter} 2>/dev/null)" ||
      exec ${jq} -cn --arg icon '${icon}' '{text: ($icon + " …"), tooltip: "response unreadable", class: "stale"}'

    exec ${jq} -cn --argjson summary "$summary" --arg icon '${icon}' '
      def rounded: (. * 10 | round / 10 | tostring);
      if $summary.present == false then
        {text: ($icon + " …"), tooltip: ($summary.lines | join("\n")), class: "stale"}
      else
        {
          text: ($icon + " "
            + (if ($summary.weight | type) == "number" then ($summary.weight | rounded) + "kg" else "?" end)
            + (if $summary.trend == "" then "" elif $summary.delta == null then " " + $summary.trend else " " + $summary.trend + ($summary.delta | tostring) end)),
          tooltip: ($summary.lines | join("\n")),
          class: $summary.state
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
