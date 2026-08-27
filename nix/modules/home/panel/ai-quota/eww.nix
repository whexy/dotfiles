# Eww quota meters (Linux).
#
# One Eww poll fetches the provider data and emits all summaries as a single
# JSON value. The visible widgets reference that poll directly, so fetching
# and rendering share one lifecycle and one interval.
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

  shared = import ./shared.nix { inherit perSystem; };
  inherit (shared) aiQuota providers;

  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;

  enabled =
    cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin) && config.dotfiles.agents.enable;

  quotaScript = pkgs.writeShellScript "eww-ai-quota" ''
    raw="$(${aiQuota} --json 2>/dev/null)" || exit 0
    ${lib.concatMapStringsSep "\n" (p: ''
      ${p.variable}="$(printf '%s\n' "$raw" | ${jq} -c -f ${summaryFilter} --arg provider ${p.name} 2>/dev/null)" || exit 0
    '') providers}
    ${jq} -cn \
      ${
        lib.concatMapStringsSep " \\\n      " (
          p: ''--argjson ${p.variable} "$'' + p.variable + ''"''
        ) providers
      } \
      '{${lib.concatMapStringsSep ", " (p: ''"${p.name}": $'' + p.variable) providers}}'
  '';

  providerDef = p: ''
    (defwidget ai-quota-${p.name} []
      (box :space-evenly false
        :class {"pill quota"
          + (jq(AI_QUOTA, ".\"${p.name}\".state == \"warning\"") ? " warning" : "")
          + (jq(AI_QUOTA, ".\"${p.name}\".state == \"critical\"") ? " critical" : "")
          + (jq(AI_QUOTA, ".\"${p.name}\".state == \"error\"") ? " error" : "")}
        :visible {jq(AI_QUOTA, ".\"${p.name}\".present")}
        :tooltip {jq(AI_QUOTA, ".\"${p.name}\".compact_lines | join(\"\\n\")")}
        (label :class "quota-icon" :text "${p.icon}")
        (progress :class "quota-bar" :orientation "h" :valign "center"
          :hexpand false :width 56 :value {jq(AI_QUOTA, ".\"${p.name}\".remaining")})
        (label :class "quota-pct" :text {round(jq(AI_QUOTA, ".\"${p.name}\".remaining"), 0)})
        (label :text "%")))
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (defpoll AI_QUOTA :interval "60s"
          :initial '{${
            lib.concatMapStringsSep "," (
              p: ''"${p.name}":{"present":false,"state":"empty","remaining":0,"compact_lines":[]}''
            ) providers
          }}'
          "${quotaScript}")
      ''
      + lib.concatMapStringsSep "\n" providerDef providers;

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
