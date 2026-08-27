# Waybar quota meters (Linux).
#
# Each visible custom module retrieves current quota data on Waybar's own
# interval and renders its provider directly.
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
    cfg.waybar.enable && cfg.linuxBar == "waybar" && (!isDarwin) && config.dotfiles.agents.enable;

  # Waybar has no generic custom slider, so render a short segmented meter.
  # summary.jq still decides what binds and provides the compact hover details.
  pillScript =
    provider: icon:
    pkgs.writeShellScript "waybar-ai-quota-${provider}" ''
      raw="$(${aiQuota} --json 2>/dev/null)" ||
        exec ${jq} -cn '{text: "", tooltip: "quota fetch failed", class: "error"}'
      summary="$(printf '%s\n' "$raw" | ${jq} -c -f ${summaryFilter} --arg provider ${provider} 2>/dev/null)" ||
        exec ${jq} -cn '{text: "", tooltip: "quota response unreadable", class: "error"}'

      exec ${jq} -cn --argjson s "$summary" --arg icon '${icon}' '
        def meter:
          (.remaining | if . < 0 then 0 elif . > 100 then 100 else . end) as $pct
          | (($pct * 6 / 100) | round) as $filled
          | ("█" * $filled) + ("░" * (6 - $filled));

        if $s.present == false then
          { text: "", tooltip: "", class: "empty" }
        else
          {
            text: ($icon + " " + ($s | meter) + " " + (($s.remaining | round) | tostring) + "%"),
            tooltip: ($s.compact_lines | join("\n")),
            class: $s.state
          }
        end'
    '';

  pillModule =
    provider: icon:
    lib.nameValuePair "custom/ai-quota-${provider}" {
      exec = pillScript provider icon;
      interval = 60;
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
      #custom-ai-quota-kimi,
      #custom-ai-quota-codex,
      #custom-ai-quota-opencode-go {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        background-color: #3c3836;
        color: #b8bb26;
        transition: all 0.3s ease;
      }

      #custom-ai-quota-kimi:hover,
      #custom-ai-quota-codex:hover,
      #custom-ai-quota-opencode-go:hover {
        background-color: #504945;
      }

      #custom-ai-quota-kimi.warning,
      #custom-ai-quota-codex.warning,
      #custom-ai-quota-opencode-go.warning {
        color: #d79921;
      }

      #custom-ai-quota-kimi.critical,
      #custom-ai-quota-codex.critical,
      #custom-ai-quota-opencode-go.critical {
        color: #fb4934;
      }

      #custom-ai-quota-kimi.error,
      #custom-ai-quota-codex.error,
      #custom-ai-quota-opencode-go.error {
        color: #928374;
      }

      /* Collapse absent providers entirely. */
      #custom-ai-quota-kimi.empty,
      #custom-ai-quota-codex.empty,
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
