# Eww quota capsules (Linux).
#
# One poll fetches every provider. Compact Material 3 capsules show all quota
# windows as stacked tracks plus the reset that can next restore availability;
# clicking a capsule toggles the shared detail app.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  showCountdown = cfg.aiQuota.showCountdown;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  shared = import ./shared.nix;
  inherit (shared) apiUrl providers updateInterval;

  curl = lib.getExe pkgs.curl;
  jq = lib.getExe pkgs.jq;
  aiQuotaPackage = pkgs.callPackage ../../../../packages/ai-quota-popup { };
  aiQuotaPopup = lib.getExe aiQuotaPackage;
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

        .quota-grok .quota-countdown {
          color: #ffffff;
        }

        .quota.error {
          color: $on-surface-variant;
        }

        .quota.error .quota-countdown {
          color: $on-surface-variant;
        }

        .quota-track.missing { opacity: 0; }

        .quota-track.gray progress { background-color: #98989d; }
        .quota-track.grayDim progress { background-color: rgba(152, 152, 157, 0.7); }
        .quota-track.grayFaint progress { background-color: rgba(152, 152, 157, 0.45); }

        .quota-track.blue progress { background-color: #007cff; }
        .quota-track.blueDim progress { background-color: rgba(0, 124, 255, 0.7); }
        .quota-track.blueFaint progress { background-color: rgba(0, 124, 255, 0.45); }

        .quota-track.green progress { background-color: #10a37f; }
        .quota-track.greenDim progress { background-color: rgba(16, 163, 127, 0.7); }
        .quota-track.greenFaint progress { background-color: rgba(16, 163, 127, 0.45); }

        .quota-track.orange progress { background-color: #d97757; }
        .quota-track.orangeDim progress { background-color: rgba(217, 119, 87, 0.7); }
        .quota-track.orangeFaint progress { background-color: rgba(217, 119, 87, 0.45); }

        .quota-track.white progress { background-color: #ffffff; }
        .quota-track.whiteDim progress { background-color: rgba(255, 255, 255, 0.7); }
        .quota-track.whiteFaint progress { background-color: rgba(255, 255, 255, 0.45); }
      '';
    };
  };
}
