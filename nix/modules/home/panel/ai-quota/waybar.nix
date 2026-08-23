# Waybar quota pills (Linux).
#
# A hidden fetcher module refreshes the shared cache every 5 minutes; each
# pill polls it once a minute and renders the best account's binding
# window (see ./summary.jq). The full account x meter matrix lives in the
# Pango tooltip. Follows the renpho pattern: settings and style are merged
# in with mkAfter, so ../waybar.nix stays quota-agnostic.
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

  aiQuota = "${perSystem.self.ai-quota}/bin/ai-quota";
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;
  cacheFile = "${config.xdg.cacheHome}/ai-quota.json";

  providers = [
    {
      name = "kimi";
      icon = "󰽥";
    }
    {
      name = "codex";
      icon = "󰚩";
    }
  ];

  enabled =
    cfg.waybar.enable
    && (!isDarwin)
    && config.dotfiles.agents.enable
    && config.dotfiles.agents.enableProxyAccounts;

  fetchScript = pkgs.writeShellScript "waybar-ai-quota-fetch" ''
    out="$(${aiQuota} --json 2>/dev/null)" || exit 0
    mkdir -p "$(dirname "${cacheFile}")"
    tmp="${cacheFile}.tmp.$$"
    printf '%s\n' "$out" > "$tmp"
    mv "$tmp" "${cacheFile}"
  '';

  # summary.jq decides WHAT matters; this wrapper formats it the way waybar
  # wants: pill text, Pango tooltip, and a CSS class per severity.
  pillScript =
    provider: icon:
    pkgs.writeShellScript "waybar-ai-quota-${provider}" ''
      cache="${cacheFile}"
      [ -f "$cache" ] || exit 0

      summary="$(${jq} -c -f ${summaryFilter} --arg provider ${provider} "$cache" 2>/dev/null)" || exit 0
      exec ${jq} -cn --argjson s "$summary" --arg icon '${icon}' '
        if $s.present == false then
          { text: "", tooltip: "", class: "empty" }
        else
          {
            text: ($icon + " " + $s.label),
            tooltip: ($s.lines | join("\n")),
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
      exec-if = "test -f ${cacheFile}";
    };
in
{
  config = lib.mkIf enabled {
    programs.waybar.settings.mainBar = {
      "modules-right" = lib.mkAfter (map (p: "custom/ai-quota-${p.name}") providers);

      "custom/ai-quota-fetch" = {
        exec = fetchScript;
        interval = 300;
      };
    }
    // builtins.listToAttrs (map (p: pillModule p.name p.icon) providers);

    programs.waybar.style = lib.mkAfter ''
      #custom-ai-quota-kimi,
      #custom-ai-quota-codex {
        color: #b8bb26;
      }

      #custom-ai-quota-kimi.warning,
      #custom-ai-quota-codex.warning {
        color: #d79921;
      }

      #custom-ai-quota-kimi.critical,
      #custom-ai-quota-codex.critical {
        color: #fb4934;
      }

      #custom-ai-quota-kimi.error,
      #custom-ai-quota-codex.error {
        color: #928374;
      }

      /* Collapse absent providers entirely */
      #custom-ai-quota-kimi.empty,
      #custom-ai-quota-codex.empty {
        padding: 0;
        margin: 0;
        min-width: 0;
        font-size: 0;
        background-color: transparent;
      }
    '';
  };
}
