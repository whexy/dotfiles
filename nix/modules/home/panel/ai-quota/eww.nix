# Eww quota meters (Linux).
#
# Eww counterpart of ./waybar.nix: each provider gets a meter widget plus a
# tooltip widget, both polling the shared JSON cache refreshed by
# updateCacheScript from ./shared.nix. Summarization lives in ./summary.jq.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  shared = import ./shared.nix {
    inherit
      config
      lib
      pkgs
      perSystem
      ;
  };

  inherit (shared)
    cacheFile
    providers
    updateCacheScript
    ;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;

  enabled =
    cfg.waybar.enable
    && cfg.linuxBar == "eww"
    && (!isDarwin)
    && config.dotfiles.agents.enable
    && config.dotfiles.agents.enableProxyAccounts;

  # Yuck variable names cannot contain hyphens (kimi -> KIMI).
  toVarName = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);

  # Same segmented meter as the Waybar module; summary.jq still decides what
  # binds and provides the compact hover details.
  meterScript =
    provider: icon:
    pkgs.writeShellScript "eww-ai-quota-${provider}" ''
      cache="${cacheFile}"
      [ -f "$cache" ] || exit 0

      summary="$(${jq} -c -f ${summaryFilter} --arg provider ${provider} "$cache" 2>/dev/null)" || exit 0
      exec ${jq} -cn --argjson s "$summary" --arg icon '${icon}' '
        def meter:
          (.remaining | if . < 0 then 0 elif . > 100 then 100 else . end) as $pct
          | (($pct * 6 / 100) | round) as $filled
          | ("█" * $filled) + ("░" * (6 - $filled));

        if $s.present == false then ""
        else $icon + " " + ($s | meter) + " " + (($s.remaining | round) | tostring) + "%"
        end'
    '';

  tooltipScript =
    provider:
    pkgs.writeShellScript "eww-ai-quota-${provider}-tooltip" ''
      cache="${cacheFile}"
      [ -f "$cache" ] || exit 0

      ${jq} -c -f ${summaryFilter} --arg provider ${provider} "$cache" 2>/dev/null |
        ${jq} -r 'if .present == false then "" else (.compact_lines | join("\n")) end'
    '';

  providerDefs = p: ''
    (defpoll ${toVarName p.name} :interval "60s" "${meterScript p.name p.icon}")
    (defpoll ${toVarName p.name}_TOOLTIP :interval "60s" "${tooltipScript p.name}")

    (defwidget ai-quota-${p.name} []
      (box :class "pill quota" :tooltip {${toVarName p.name}_TOOLTIP}
        (label :text ${toVarName p.name})))
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        ; Hidden poll keeping the shared cache fresh; its value is unused.
        (defpoll AI_QUOTA_FETCH :interval "300s" "${updateCacheScript}")
      ''
      + lib.concatMapStringsSep "\n" providerDefs providers;

      right = lib.mkAfter (map (p: "ai-quota-${p.name}") providers);
    };
  };
}
