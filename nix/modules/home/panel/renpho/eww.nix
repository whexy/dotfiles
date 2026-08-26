# Renpho weight widget for Eww (Linux).
#
# Eww counterpart of ./waybar.nix: one widget for the weight readout plus a
# tooltip widget, both polling the renpho-health cache through ./summary.jq.
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

  enabled = cfg.renpho.enable && cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin);

  cacheArgs = "cache=${lib.escapeShellArg hcfg.cachePath}";

  weightScript = pkgs.writeShellScript "eww-renpho-weight" ''
    ${cacheArgs}

    if [ ! -f "$cache" ]; then
      printf '${icon} …\n'
      exit 0
    fi

    summary="$(${jq} -c --argjson summary_count ${toString summaryCount} -f ${summaryFilter} "$cache" 2>/dev/null)" ||
      { printf '${icon} …\n'; exit 0; }

    # Raw output: -c would JSON-encode the label, leaving literal quotes.
    exec ${jq} -rn --argjson summary "$summary" --arg icon '${icon}' '
      def rounded: (. * 10 | round / 10 | tostring);
      if $summary.present == false then ($icon + " …")
      else
        $icon + " "
        + (if ($summary.weight | type) == "number" then ($summary.weight | rounded) + "kg" else "?" end)
        + (if $summary.trend == "" then ""
           elif $summary.delta == null then " " + $summary.trend
           else " " + $summary.trend + ($summary.delta | tostring)
           end)
      end'
  '';

  tooltipScript = pkgs.writeShellScript "eww-renpho-tooltip" ''
    ${cacheArgs}
    [ -f "$cache" ] || exit 0

    ${jq} -c --argjson summary_count ${toString summaryCount} -f ${summaryFilter} "$cache" 2>/dev/null |
      ${jq} -r 'if .present == false then "" else (.lines | join("\n")) end'
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (defpoll RENPHO :interval "300s" "${weightScript}")
        (defpoll RENPHO_TOOLTIP :interval "300s" "${tooltipScript}")

        (defwidget renpho []
          (box :class "pill renpho" :tooltip {RENPHO_TOOLTIP}
            (label :text RENPHO)))
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
