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
    cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin) && config.dotfiles.agents.enable;

  # Yuck variable names cannot contain hyphens (kimi -> KIMI).
  toVarName = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);

  # Emits one JSON record per provider so the widget can drive a real
  # progress bar and per-state classes. summary.jq still decides what binds;
  # the tooltip poll provides the compact hover details.
  meterScript =
    provider:
    pkgs.writeShellScript "eww-ai-quota-${provider}" ''
      cache="${cacheFile}"
      [ -f "$cache" ] || exit 0

      summary="$(${jq} -c -f ${summaryFilter} --arg provider ${provider} "$cache" 2>/dev/null)" || exit 0
      exec ${jq} -cn --argjson s "$summary" '
        ($s.remaining // 0 | round | if . < 0 then 0 elif . > 100 then 100 else . end) as $r
        | if $s.present == false then
            {present: false, state: "empty", remaining: 0}
          else
            {present: true, state: $s.state, remaining: $r}
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

  # eww's jq() keeps JSON quoting on string results, so the state class
  # comes from boolean filters and the percentage renders as a number plus
  # a literal "%" label.
  providerDefs = p: ''
    (defpoll ${toVarName p.name} :interval "60s"
      :initial '{"present": false, "state": "empty", "remaining": 0}'
      "${meterScript p.name}")
    (defpoll ${toVarName p.name}_TOOLTIP :interval "60s" "${tooltipScript p.name}")

    (defwidget ai-quota-${p.name} []
      (box :space-evenly false
        :class {"pill quota"
          + (jq(${toVarName p.name}, ".state == \"warning\"") ? " warning" : "")
          + (jq(${toVarName p.name}, ".state == \"critical\"") ? " critical" : "")
          + (jq(${toVarName p.name}, ".state == \"error\"") ? " error" : "")}
        :visible {jq(${toVarName p.name}, ".present")}
        :tooltip {${toVarName p.name}_TOOLTIP}
        (label :class "quota-icon" :text "${p.icon}")
        (progress :class "quota-bar" :orientation "h" :valign "center"
          :hexpand false :width 56 :value {jq(${toVarName p.name}, ".remaining")})
        (label :class "quota-pct" :text {jq(${toVarName p.name}, ".remaining")})
        (label :text "%")))
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        ; Hidden poll keeping the shared cache fresh; its value is unused.
        (defpoll AI_QUOTA_FETCH :interval "60s" "${updateCacheScript}")
      ''
      + lib.concatMapStringsSep "\n" providerDefs providers;

      left = lib.mkAfter (map (p: "ai-quota-${p.name}") providers);

      styles = ''
        // Material You linear progress: tonal track, rounded fill tinted by
        // quota state (matches summary.jq's ok/warning/critical/error).
        .quota {
          color: $on-surface;
        }

        .quota-icon {
          margin-right: 6px;
        }

        .quota-pct {
          margin-left: 6px;
        }

        // GTK progressbars request ~150px by default. The widget and trough
        // establish the compact track width; the progress node must remain
        // unconstrained so GTK can size it to the current percentage.
        .quota-bar,
        .quota-bar trough {
          min-width: 56px;
        }

        .quota-bar trough {
          min-height: 6px;
          border-radius: 3px;
          background-color: $secondary-container;
        }

        .quota-bar progress {
          min-width: 0;
          min-height: 6px;
          border-radius: 3px;
          background-color: $primary;
        }

        .quota.warning {
          color: $warning;
        }

        .quota.warning .quota-bar progress {
          background-color: $warning;
        }

        .quota.critical {
          color: $error;
        }

        .quota.critical .quota-bar progress {
          background-color: $error;
        }

        .quota.error {
          color: $on-surface-variant;
        }
      '';
    };
  };
}
