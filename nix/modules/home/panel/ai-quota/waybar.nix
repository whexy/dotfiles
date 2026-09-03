# Waybar quota meters (Linux).
#
# Each visible custom module retrieves current quota data on Waybar's own
# interval and renders its provider directly.
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
  summaryFilter = ./summary.jq;

  enabled =
    cfg.waybar.enable && cfg.linuxBar == "waybar" && (!isDarwin) && config.dotfiles.agents.enable;

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

  pillModule =
    provider: icon:
    lib.nameValuePair "custom/ai-quota-${provider}" {
      exec = pillScript provider icon;
      interval = updateInterval;
      return-type = "json";
      escape = false;
      format = "{}";
      tooltip = true;
    };
in
{
  config = lib.mkIf enabled {
    programs.waybar.settings.mainBar = {
      "modules-right" = lib.mkAfter (map (p: "custom/ai-quota-${p.name}") providers);
    }
    // builtins.listToAttrs (map (p: pillModule p.name p.icon) providers);

    programs.waybar.style = lib.mkAfter ''
      #custom-ai-quota-claude,
      #custom-ai-quota-kimi,
      #custom-ai-quota-codex,
      #custom-ai-quota-antigravity,
      #custom-ai-quota-grok,
      #custom-ai-quota-opencode-go {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        background-color: #3c3836;
        transition: all 0.3s ease;
      }

      #custom-ai-quota-claude {
        color: #d97757;
      }

      #custom-ai-quota-kimi {
        color: #007cff;
      }

      #custom-ai-quota-codex {
        color: #10a37f;
      }

      #custom-ai-quota-antigravity {
        color: #98989d;
      }

      #custom-ai-quota-grok {
        color: #ffffff;
      }

      #custom-ai-quota-opencode-go {
        color: #98989d;
      }

      #custom-ai-quota-claude:hover,
      #custom-ai-quota-kimi:hover,
      #custom-ai-quota-codex:hover,
      #custom-ai-quota-antigravity:hover,
      #custom-ai-quota-grok:hover,
      #custom-ai-quota-opencode-go:hover {
        background-color: #504945;
      }

      #custom-ai-quota-claude.error,
      #custom-ai-quota-kimi.error,
      #custom-ai-quota-codex.error,
      #custom-ai-quota-antigravity.error,
      #custom-ai-quota-grok.error,
      #custom-ai-quota-opencode-go.error {
        color: #928374;
      }

      /* Collapse absent providers entirely. */
      #custom-ai-quota-claude.empty,
      #custom-ai-quota-kimi.empty,
      #custom-ai-quota-codex.empty,
      #custom-ai-quota-antigravity.empty,
      #custom-ai-quota-grok.empty,
      #custom-ai-quota-opencode-go.empty {
        padding: 0;
        margin: 0;
        min-width: 0;
        font-size: 0;
        background-color: transparent;
      }
    '';
  };
}
