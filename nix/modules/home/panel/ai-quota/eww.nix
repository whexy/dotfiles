# Eww quota capsules (Linux).
#
# One poll fetches every provider. Compact Material 3 capsules show all quota
# windows as stacked tracks plus the reset that can next restore availability;
# clicking a capsule toggles a larger read-only details card.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  shared = import ./shared.nix;
  inherit (shared) apiUrl providers updateInterval;

  curl = lib.getExe pkgs.curl;
  eww = lib.getExe pkgs.eww;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;

  enabled =
    cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin) && config.dotfiles.agents.enable;

  quotaScript = pkgs.writeShellScript "eww-ai-quota" ''
    raw="$(${curl} -fsS --max-time 10 ${lib.escapeShellArg apiUrl} 2>/dev/null)" || exit 0
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

  detailsWindows = map (p: "ai-quota-details-${p.name}") providers;

  toggleScript =
    provider:
    pkgs.writeShellScript "eww-ai-quota-toggle-${provider}" ''
      ${eww} poll AI_QUOTA >/dev/null 2>&1 &
      active="$(${eww} active-windows 2>/dev/null || true)"
      case "$active" in
        *"ai-quota-details-${provider}: ai-quota-details-${provider}"*)
          exec ${eww} close ai-quota-details-${provider}
          ;;
        *)
          ${eww} close ${lib.concatStringsSep " " detailsWindows} >/dev/null 2>&1 || true
          exec ${eww} open ai-quota-details-${provider}
          ;;
      esac
    '';

  providerDef = p: ''
    (defwidget ai-quota-${p.name} []
      (eventbox :cursor "pointer" :timeout "1s"
        :onclick "${toggleScript p.name}"
        (box :space-evenly false
          :class {"pill quota quota-${p.name}"
            + (jq(AI_QUOTA, ".\"${p.name}\".display_meter.state == \"warning\"") ? " warning" : "")
            + (jq(AI_QUOTA, ".\"${p.name}\".display_meter.state == \"critical\"") ? " critical" : "")
            + (jq(AI_QUOTA, ".\"${p.name}\".state == \"error\"") ? " error" : "")}
          :visible {jq(AI_QUOTA, ".\"${p.name}\".present")}
          (image :class "quota-icon" :path "${p.logo}"
            :image-width 16 :image-height 16 :preserve-aspect-ratio true)
          (box :class "quota-tracks" :orientation "v" :spacing 2
            :space-evenly false :valign "center"
            (for meter in {jq(AI_QUOTA, ".\"${p.name}\".compact_meters[:3]")}
              (progress :class {"quota-track " + meter.color}
                :orientation "h" :width 58 :value {meter.remaining})))
          (label :class "quota-countdown"
            :text {jq(AI_QUOTA, ".\"${p.name}\".display_meter.countdown // \"—\"", "r")}))))

    (defwidget ai-quota-details-${p.name} []
      (box :class "quota-details" :orientation "v" :space-evenly false
        (box :class "quota-details-header" :space-evenly false
          (image :path "${p.logo}" :image-width 20 :image-height 20
            :preserve-aspect-ratio true)
          (box :class "quota-details-heading" :orientation "v" :space-evenly false
            (label :class "quota-details-title" :halign "start" :text "${p.title}")
            (label :class "quota-details-subtitle" :halign "start" :text "Quota windows"))
          (button :class "quota-details-close"
            :onclick "${eww} close ai-quota-details-${p.name}" "󰅖"))
        (box :class "quota-details-meters" :orientation "v" :spacing 10
          :space-evenly false
          (for meter in {jq(AI_QUOTA, ".\"${p.name}\".compact_meters[:3]")}
            (box :class "quota-detail-meter" :orientation "v" :space-evenly false
              (box :class "quota-detail-labels" :space-evenly false
                (label :class {"quota-detail-name " + meter.color}
                  :halign "start" :hexpand true :text {meter.label})
                (label :class "quota-detail-value" :halign "end"
                  :text {round(meter.remaining, 0) + "%"}))
              (progress :class {"quota-detail-bar " + meter.color}
                :orientation "h" :value {meter.remaining})
              (label :class "quota-detail-reset" :halign "start"
                :text {meter.reset_label}))))))

    (defwindow ai-quota-details-${p.name}
      :monitor 0
      :geometry (geometry :x "8px" :y "-36px" :width "300px" :height "224px"
        :anchor "bottom left")
      :stacking "overlay"
      :focusable "none"
      (ai-quota-details-${p.name}))
  '';
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.eww = {
      defs = ''
        (defpoll AI_QUOTA :interval "${toString updateInterval}s"
          :initial '{${
            lib.concatMapStringsSep "," (
              p:
              ''"${p.name}":{"present":false,"state":"empty","remaining":0,"display_meter":null,"compact_lines":[],"compact_meters":[]}''
            ) providers
          }}'
          "${quotaScript}")
      ''
      + lib.concatMapStringsSep "\n" providerDef providers;

      left = lib.mkAfter (map (p: "ai-quota-${p.name}") providers);

      styles = ''
        // Material 3 compact status capsules. Each native progress bar is one
        // quota window; longer windows use lower-emphasis accent tones.
        .quota {
          color: $on-surface;
          padding: 2px 9px;
          transition: background-color 150ms ease;
        }

        .quota:hover {
          background-color: $surface-container-highest;
        }

        .quota-icon {
          margin-right: 8px;
        }

        .quota-tracks {
          min-width: 58px;
        }

        .quota-track,
        .quota-track trough {
          min-width: 58px;
        }

        .quota-track trough {
          min-height: 3px;
          border-radius: 2px;
          background-color: rgba(202, 196, 208, 0.18);
        }

        .quota-track progress {
          min-width: 0;
          min-height: 3px;
          border-radius: 2px;
        }

        .quota-countdown {
          min-width: 46px;
          margin-left: 8px;
          font-size: 11px;
          font-weight: bold;
        }

        .quota-claude .quota-countdown {
          color: #d97757;
        }

        .quota-kimi .quota-countdown {
          color: #007cff;
        }

        .quota-codex .quota-countdown {
          color: #10a37f;
        }

        .quota-antigravity .quota-countdown {
          color: #98989d;
        }

        .quota.error {
          color: $on-surface-variant;
        }

        .quota.error .quota-countdown {
          color: $on-surface-variant;
        }

        .quota-track.gray progress,
        .quota-detail-bar.gray progress {
          background-color: #98989d;
        }

        .quota-track.grayDim progress,
        .quota-detail-bar.grayDim progress {
          background-color: rgba(152, 152, 157, 0.7);
        }

        .quota-track.grayFaint progress,
        .quota-detail-bar.grayFaint progress {
          background-color: rgba(152, 152, 157, 0.45);
        }

        .quota-track.blue progress,
        .quota-detail-bar.blue progress {
          background-color: #007cff;
        }

        .quota-track.blueDim progress,
        .quota-detail-bar.blueDim progress {
          background-color: rgba(0, 124, 255, 0.7);
        }

        .quota-track.blueFaint progress,
        .quota-detail-bar.blueFaint progress {
          background-color: rgba(0, 124, 255, 0.45);
        }

        .quota-track.green progress,
        .quota-detail-bar.green progress {
          background-color: #10a37f;
        }

        .quota-track.greenDim progress,
        .quota-detail-bar.greenDim progress {
          background-color: rgba(16, 163, 127, 0.7);
        }

        .quota-track.greenFaint progress,
        .quota-detail-bar.greenFaint progress {
          background-color: rgba(16, 163, 127, 0.45);
        }

        .quota-track.orange progress,
        .quota-detail-bar.orange progress {
          background-color: #d97757;
        }

        .quota-track.orangeDim progress,
        .quota-detail-bar.orangeDim progress {
          background-color: rgba(217, 119, 87, 0.7);
        }

        .quota-track.orangeFaint progress,
        .quota-detail-bar.orangeFaint progress {
          background-color: rgba(217, 119, 87, 0.45);
        }

        // Material 3 elevated card used by the click-toggle details window.
        #ai-quota-details-claude,
        #ai-quota-details-kimi,
        #ai-quota-details-codex,
        #ai-quota-details-antigravity {
          background-color: transparent;
        }

        .quota-details {
          background-color: $surface-container-high;
          color: $on-surface;
          border: 1px solid rgba(202, 196, 208, 0.24);
          border-radius: 20px;
          padding: 14px 16px;
          box-shadow: 0 8px 24px rgba(0, 0, 0, 0.42);
        }

        .quota-details-header {
          margin-bottom: 10px;
        }

        .quota-details-heading {
          margin-left: 10px;
        }

        .quota-details-title {
          font-size: 13px;
          font-weight: bold;
        }

        .quota-details-subtitle,
        .quota-detail-reset {
          color: $on-surface-variant;
          font-size: 10px;
        }

        .quota-details-close {
          min-width: 28px;
          min-height: 28px;
          margin-left: 8px;
          border-radius: 14px;
          color: $on-surface-variant;
        }

        .quota-details-close:hover {
          background-color: $surface-container-highest;
          color: $on-surface;
        }

        .quota-detail-labels {
          margin-bottom: 3px;
        }

        .quota-detail-name,
        .quota-detail-value {
          font-size: 11px;
          font-weight: bold;
        }

        .quota-detail-bar,
        .quota-detail-bar trough {
          min-width: 266px;
        }

        .quota-detail-bar trough {
          min-height: 6px;
          border-radius: 3px;
          background-color: $surface-container-highest;
        }

        .quota-detail-bar progress {
          min-width: 0;
          min-height: 6px;
          border-radius: 3px;
        }

        .quota-detail-reset {
          margin-top: 2px;
        }
      '';
    };
  };
}
