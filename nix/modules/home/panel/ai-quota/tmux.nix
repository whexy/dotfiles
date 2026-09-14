# tmux status-bar quota meters (servers without a desktop bar).
#
# tmux re-runs `#()` on every status-interval, so the script caches the API
# response for updateInterval seconds and renders all providers in one call.
# Colors are resolved from the catppuccin theme options at render time because
# `#()` output is not format-expanded again.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;
  showCountdown = cfg.aiQuota.showCountdown;

  shared = import ./shared.nix;
  inherit (shared) apiUrl providers updateInterval;

  curl = lib.getExe pkgs.curl;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;

  enabled = config.dotfiles.terminal.tmux.enable && config.dotfiles.agents.enable;

  providerArgs = lib.concatMapStringsSep " " (
    p: "${lib.escapeShellArg p.name}:${lib.escapeShellArg p.icon}"
  ) providers;

  script = pkgs.writeShellScript "tmux-ai-quota" ''
    cache="''${XDG_RUNTIME_DIR:-/tmp}/tmux-ai-quota-''${UID:-$(id -u)}.json"

    # Theme options may themselves be formats, so expand them through tmux.
    # Empty separators are legal, so split on a non-whitespace delimiter.
    IFS='|' read -r crust fg text_bg left middle right ok warn crit err < <(
      tmux display -p '#{E:@thm_crust}|#{E:@thm_fg}|#{E:@catppuccin_status_module_text_bg}|#{E:@catppuccin_status_left_separator}|#{E:@catppuccin_status_middle_separator}|#{E:@catppuccin_status_right_separator}|#{E:@thm_green}|#{E:@thm_yellow}|#{E:@thm_red}|#{E:@thm_overlay_0}'
    )

    fresh=0
    if [ -s "$cache" ]; then
      now=$(date +%s); mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache")
      [ $((now - mtime)) -lt ${toString updateInterval} ] && fresh=1
    fi
    if [ "$fresh" = 0 ]; then
      ${curl} -fsS --max-time 10 ${lib.escapeShellArg apiUrl} -o "$cache.tmp" 2>/dev/null &&
        mv "$cache.tmp" "$cache" || rm -f "$cache.tmp"
    fi
    [ -s "$cache" ] || exit 0

    for spec in ${providerArgs}; do
      provider="''${spec%%:*}"; icon="''${spec#*:}"
      summary="$(${jq} -c -f ${summaryFilter} --arg provider "$provider" "$cache" 2>/dev/null)" || continue
      [ "$(printf '%s' "$summary" | ${jq} -r .present)" = true ] || continue
      state="$(printf '%s' "$summary" | ${jq} -r .state)"
      case "$state" in
        ok) accent="$ok" ;;
        warning) accent="$warn" ;;
        critical) accent="$crit" ;;
        *) accent="$err" ;;
      esac
      if [ "$state" = error ]; then
        text="…"
      else
        text="$(printf '%s' "$summary" | ${jq} -r '
          (.remaining | round | tostring) + "%"
          ${lib.optionalString showCountdown ''+ " " + (.display_meter.countdown // "—")''}')"
      fi
      printf '#[fg=%s]%s#[fg=%s,bg=%s]%s%s#[fg=%s,bg=%s] %s #[fg=%s]%s' \
        "$accent" "$left" "$crust" "$accent" "$icon" "$middle" \
        "$fg" "$text_bg" "$text" "$text_bg" "$right"
    done
  '';
in
{
  config = lib.mkIf enabled {
    # Appended after the plugin block so catppuccin's theme options exist.
    programs.tmux.extraConfig = lib.mkAfter ''
      set -ag status-right "#(${script})"
      set -g status-right-length 200
    '';
  };
}
