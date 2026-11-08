# Waybar quota meters (Linux).
#
# Each visible custom module retrieves current quota data on Waybar's own
# interval and renders its provider directly.
{
  config,
  lib,
  perSystem,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;
  inherit (import ../../desktop/style.nix) colors;
  aiQuotaPackage = perSystem.self.ai-quota-popup;
  showCountdown = cfg.aiQuota.showCountdown;

  inherit (aiQuotaPackage)
    apiUrl
    providers
    summaryFilter
    updateInterval
    ;

  curl = lib.getExe pkgs.curl;
  jq = lib.getExe pkgs.jq;
  aiQuotaPopup = lib.getExe aiQuotaPackage;

  enabled = cfg.renderer == "waybar" && cfg.aiQuota.enable;

  # Waybar has no generic custom slider, so render a short segmented meter.
  # summary.jq still decides what binds and provides the compact hover details.
  pillScript =
    provider: icon:
    pkgs.writeShellScript "waybar-ai-quota-${provider}" ''
      raw="$(${curl} -fsS --max-time 10 ${lib.escapeShellArg apiUrl} 2>/dev/null)" ||
        exec ${jq} -cn --arg icon '${icon}' \
          '{text: ($icon + " …"), tooltip: "quota fetch failed", class: "error"}'
      summary="$(printf '%s\n' "$raw" | ${jq} -c -f ${summaryFilter} --arg provider ${provider} 2>/dev/null)" ||
        exec ${jq} -cn --arg icon '${icon}' \
          '{text: ($icon + " …"), tooltip: "quota response unreadable", class: "error"}'

      exec ${jq} -cn --argjson s "$summary" --arg icon '${icon}' '
        def meter:
          (.remaining | if . < 0 then 0 elif . > 100 then 100 else . end) as $pct
          | (($pct * 6 / 100) | round) as $filled
          | ("█" * $filled) + ("░" * (6 - $filled));

        if $s.present == false then
          { text: "", tooltip: "", class: "empty" }
        elif $s.state == "error" then
          {
            text: ($icon + " …"),
            tooltip: ($s.compact_lines | join("\n")),
            class: "error"
          }
        else
          {
            text: ($icon + " " + ($s | meter) + " " + (($s.remaining | round) | tostring) + "%"${lib.optionalString showCountdown ''+ " " + ($s.display_meter.countdown // "—")''}),
            tooltip: ($s.compact_lines | join("\n")),
            class: $s.state
          }
        end'
    '';

  selectors =
    state: lib.concatMapStringsSep ",\n" (p: "#custom-ai-quota-${p.name}${state}") providers;

  pillModule =
    provider: icon:
    lib.nameValuePair "custom/ai-quota-${provider}" {
      exec = pillScript provider icon;
      interval = updateInterval;
      return-type = "json";
      escape = false;
      format = "{}";
      tooltip = true;
      on-click = "${aiQuotaPopup} --toggle ${provider}";
    };
in
{
  config = lib.mkIf enabled {
    home.packages = [ aiQuotaPackage ];

    programs.waybar.settings.mainBar = {
      "modules-right" = lib.mkAfter (map (p: "custom/ai-quota-${p.name}") providers);
    }
    // builtins.listToAttrs (map (p: pillModule p.name p.icon) providers);

    programs.waybar.style = lib.mkAfter (
      ''
        ${selectors ""} {
          padding: 2px 10px;
          margin: 3px 2px;
          border-radius: 10px;
          background-color: ${colors.bg1};
          transition: all 0.3s ease;
        }

        ${selectors ":hover"} {
          background-color: ${colors.bg2};
        }

        ${selectors ".error"} {
          color: ${colors.gray};
        }

        /* Collapse absent providers entirely. */
        ${selectors ".empty"} {
          padding: 0;
          margin: 0;
          min-width: 0;
          font-size: 0;
          background-color: transparent;
        }
      ''
      + lib.concatMapStrings (p: ''
        #custom-ai-quota-${p.name} {
          color: ${p.accent.hex};
        }
      '') providers
    );
  };
}
