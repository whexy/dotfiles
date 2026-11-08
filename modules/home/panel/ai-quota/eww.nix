# Eww quota capsules (Linux).
#
# One poll fetches every provider. Compact Material 3 capsules show all quota
# windows as stacked tracks plus the reset that can next restore availability;
# clicking a capsule toggles the shared detail app.
{
  config,
  lib,
  perSystem,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;
  aiQuotaPackage = perSystem.self.ai-quota-popup;
  showCountdown = cfg.aiQuota.showCountdown;

  inherit (aiQuotaPackage)
    accents
    apiUrl
    providers
    summaryFilter
    updateInterval
    ;

  curl = lib.getExe pkgs.curl;
  jq = lib.getExe pkgs.jq;
  aiQuotaPopup = lib.getExe aiQuotaPackage;

  enabled = cfg.renderer == "eww" && cfg.aiQuota.enable;

  quotaScript = pkgs.writeShellScript "eww-ai-quota" ''
    raw="$(${curl} -fsS --max-time 10 ${lib.escapeShellArg apiUrl} 2>/dev/null)" || exit 0
    ${lib.concatMapStringsSep "\n" (p: ''
      ${p.variable}="$(printf '%s\n' "$raw" | ${jq} -c -f ${summaryFilter} --arg provider ${p.name} --arg accent ${p.accent.name} 2>/dev/null)" || exit 0
    '') providers}
    ${jq} -cn \
      ${
        lib.concatMapStringsSep " \\\n      " (
          p: ''--argjson ${p.variable} "$'' + p.variable + ''"''
        ) providers
      } \
      '{${lib.concatMapStringsSep ", " (p: ''"${p.name}": $'' + p.variable) providers}}'
  '';

  countdownRules = lib.concatMapStringsSep "\n" (p: ''
    .quota-${p.name} .quota-countdown {
      color: ${p.accent.hex};
    }
  '') providers;

  # Windows further from binding are drawn in fainter tones of the accent.
  rgb =
    hex:
    lib.concatMapStringsSep ", "
      (i: toString (lib.fromHexString (builtins.substring (1 + 2 * i) 2 hex)))
      [
        0
        1
        2
      ];
  trackRules = lib.removeSuffix "\n" (
    lib.concatMapStringsSep "\n" (a: ''
      .quota-track.${a.name} progress { background-color: ${a.hex}; }
      .quota-track.${a.name}Dim progress { background-color: rgba(${rgb a.hex}, 0.7); }
      .quota-track.${a.name}Faint progress { background-color: rgba(${rgb a.hex}, 0.45); }
    '') accents
  );

  providerDef = p: ''
    (defwidget ai-quota-${p.name} []
      (eventbox :cursor "pointer" :timeout "1s"
        :onclick "${aiQuotaPopup} --toggle ${p.name}"
        (box :space-evenly false
          :class {"pill quota quota-${p.name}"
            + (jq(AI_QUOTA, ".\"${p.name}\".display_meter.state == \"warning\"") ? " warning" : "")
            + (jq(AI_QUOTA, ".\"${p.name}\".display_meter.state == \"critical\"") ? " critical" : "")
            + (jq(AI_QUOTA, ".\"${p.name}\".state == \"error\"") ? " error" : "")}
          :visible {jq(AI_QUOTA, ".\"${p.name}\".present")}
          (image :class "quota-icon" :path "${p.logo}"
            :image-width 16 :image-height 16 :preserve-aspect-ratio true)
          (box :class {"quota-tracks cols-"
              + jq(AI_QUOTA, ".\"${p.name}\".columns | length")}
            :orientation "h" :spacing 2
            :width 58 :space-evenly true :valign "center"
            (for column in {jq(AI_QUOTA, ".\"${p.name}\".columns // []")}
              (box :orientation "v" :spacing 2 :space-evenly false
                (for meter in {column.meters}
                  (progress :class {"quota-track " + (meter?.color ?: "missing")}
                    :orientation "h" :value {meter?.remaining ?: 0})))))
          ${lib.optionalString showCountdown ''
            (label :class "quota-countdown"
              :text {jq(AI_QUOTA, ".\"${p.name}\".display_meter.countdown // \"—\"", "r")})
          ''})))
  '';
in
{
  config = lib.mkIf enabled {
    home.packages = [ aiQuotaPackage ];

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
          min-width: 0;
        }

        // GtkProgressBar carries a large intrinsic minimum width, so the pill
        // would otherwise grow with each account column. Divide the 58px track
        // area by the column count to keep every pill the same width.
        .quota-tracks.cols-1 .quota-track,
        .quota-tracks.cols-1 .quota-track trough {
          min-width: 58px;
        }

        .quota-tracks.cols-2 .quota-track,
        .quota-tracks.cols-2 .quota-track trough {
          min-width: 28px;
        }

        .quota-tracks.cols-3 .quota-track,
        .quota-tracks.cols-3 .quota-track trough {
          min-width: 18px;
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

        ${countdownRules}
        .quota.error {
          color: $on-surface-variant;
        }

        .quota.error .quota-countdown {
          color: $on-surface-variant;
        }

        .quota-track.missing { opacity: 0; }

        ${trackRules}
      '';
    };
  };
}
