# tmux status-bar quota pills (servers without a desktop bar).
#
# tmux re-runs `#()` on every status-interval, so the script caches the API
# response for updateInterval seconds and renders all providers in one call.
# Colors come from the catppuccin theme options at render time because `#()`
# output is not format-expanded again.
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

  # Catppuccin palette slot used for each provider's name (brand-ish hues).
  accent = {
    claude = "peach";
    kimi = "blue";
    codex = "green";
    antigravity = "mauve";
    grok = "fg";
  };

  providerArgs = lib.concatMapStringsSep " " (
    p: lib.escapeShellArg "${p.name}:${p.title}:${accent.${p.name} or "fg"}"
  ) providers;

  script = pkgs.writeShellScript "tmux-ai-quota" ''
    cache="''${XDG_RUNTIME_DIR:-/tmp}/tmux-ai-quota-''${UID:-$(id -u)}.json"

    # Theme options may themselves be formats, so expand them through tmux.
    IFS='|' read -r bg name_bg pct_bg fg dim warn crit err \
      c_peach c_blue c_green c_mauve c_fg < <(
      tmux display -p '#{E:@catppuccin_status_background}|#{E:@thm_surface_1}|#{E:@thm_surface_0}|#{E:@thm_fg}|#{E:@thm_overlay_1}|#{E:@thm_yellow}|#{E:@thm_red}|#{E:@thm_overlay_0}|#{E:@thm_peach}|#{E:@thm_blue}|#{E:@thm_green}|#{E:@thm_mauve}|#{E:@thm_fg}'
    )
    [ "$bg" = default ] || [ -z "$bg" ] && bg="$(tmux display -p '#{E:@thm_mantle}')"
    # Powerline half-circles; catppuccin's own right separator is a plain space.
    lcap=$'\ue0b6'; rcap=$'\ue0b4'

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

    first=1
    for spec in ${providerArgs}; do
      IFS=: read -r provider title color <<< "$spec"
      eval "name_fg=\$c_$color"
      summary="$(${jq} -c -f ${summaryFilter} --arg provider "$provider" "$cache" 2>/dev/null)" || continue
      [ "$(printf '%s' "$summary" | ${jq} -r .present)" = true ] || continue
      IFS='|' read -r state remaining countdown < <(printf '%s' "$summary" | ${jq} -r '
        [.state, ((.remaining // 0) | round | tostring), (.display_meter.countdown // "—")] | join("|")')

      case "$state" in
        ok) pct_fg="$fg" ;;
        warning) pct_fg="$warn" ;;
        critical) pct_fg="$crit" ;;
        *) pct_fg="$err" ;;
      esac

      if [ "$state" = error ]; then
        body="#[fg=$err]--"
      else
        body="#[fg=$pct_fg,bold]$remaining%#[nobold]"
        ${lib.optionalString showCountdown ''body="$body #[fg=$dim]$countdown"''}
      fi

      [ "$first" = 1 ] || printf ' '
      first=0
      printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s,bold]%s#[nobold] #[bg=%s] %s#[fg=%s,bg=%s]%s' \
        "$name_bg" "$bg" "$lcap" "$name_fg" "$name_bg" "$title" "$pct_bg" "$body" "$pct_bg" "$bg" "$rcap"
    done
  '';
in
{
  config = lib.mkIf enabled {
    # Appended after the plugin block so catppuccin's theme options exist.
    programs.tmux.extraConfig = lib.mkAfter ''
      set -g status-right "#(${script})"
    '';
  };
}
