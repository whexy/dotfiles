# tmux status-bar quota pills (servers without a desktop bar).
#
# tmux re-runs `#()` on every status redraw, up to once a second per client,
# so the script caches the API response for updateInterval seconds and reuses
# its rendered pills until that response or the theme changes. The pills are a
# function of those two alone: even the countdown comes from the response's
# reset_in, not the clock.
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

  # summary.jq is a whole program over $provider, so it nests as a function
  # body and one jq run summarizes every pill. A record it cannot summarize
  # drops only its own pill.
  pillFilter = pkgs.writeText "tmux-ai-quota.jq" ''
    def summary($provider):
    ${builtins.readFile ./summary.jq}
    ;
    . as $quota
    | $ARGS.positional[]
    | split(":") as [$provider, $title, $color]
    | $quota
    | (try summary($provider) catch {present: false})
    | select(.present == true)
    | [$title, $color, .state, ((.remaining // 0) | round | tostring),
       (.display_meter.countdown // "—")]
    | join("|")
  '';

  script = pkgs.writeShellScript "tmux-ai-quota" ''
    # macOS has no XDG_RUNTIME_DIR but a per-user TMPDIR; /tmp is shared.
    cache="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}/tmux-ai-quota-''${UID:-$(id -u)}.json"
    rendered="''${cache%.json}.status"

    # Theme options may themselves be formats, so expand them through tmux.
    theme="$(tmux display -p '#{E:@catppuccin_status_background}|#{E:@thm_surface_1}|#{E:@thm_surface_0}|#{E:@thm_fg}|#{E:@thm_overlay_1}|#{E:@thm_yellow}|#{E:@thm_red}|#{E:@thm_overlay_0}|#{E:@thm_peach}|#{E:@thm_blue}|#{E:@thm_green}|#{E:@thm_mauve}|#{E:@thm_fg}|#{E:@thm_mantle}')"
    IFS='|' read -r bg name_bg pct_bg fg dim warn crit err \
      c_peach c_blue c_green c_mauve c_fg mantle <<< "$theme"
    [ "$bg" = default ] || [ -z "$bg" ] && bg="$mantle"
    # Powerline half-circles; catppuccin's own right separator is a plain space.
    lcap=$'\ue0b6'; rcap=$'\ue0b4'

    # The cache is only ever replaced, so inode and mtime identify a response.
    identify() { stat -c '%i %Y' "$cache" 2>/dev/null || stat -f '%i %m' "$cache" 2>/dev/null; }
    fresh=0
    if [ -s "$cache" ]; then
      read -r ino mtime < <(identify)
      [ $(($(date +%s) - mtime)) -lt ${toString updateInterval} ] && fresh=1
    fi
    # curl -o follows a symlink planted at a predictable name; download into
    # a fresh file and rename it over the cache instead.
    if [ "$fresh" = 0 ] && tmp="$(mktemp "$cache.XXXXXX")"; then
      ${curl} -fsS --max-time 10 ${lib.escapeShellArg apiUrl} -o "$tmp" 2>/dev/null &&
        mv "$tmp" "$cache" || rm -f "$tmp"
      read -r ino mtime < <(identify)
    fi
    [ -s "$cache" ] || exit 0

    key="$ino $mtime $theme"
    if { IFS= read -r seen && IFS= read -r pills; } 2>/dev/null < "$rendered" && [ "$seen" = "$key" ]; then
      printf '%s' "$pills"
      exit 0
    fi

    pills=
    while IFS='|' read -r title color state remaining countdown; do
      eval "name_fg=\$c_$color"

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

      printf -v pill '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s,bold]%s#[nobold] #[bg=%s] %s#[fg=%s,bg=%s]%s' \
        "$name_bg" "$bg" "$lcap" "$name_fg" "$name_bg" "$title" "$pct_bg" "$body" "$pct_bg" "$bg" "$rcap"
      pills="''${pills:+$pills }$pill"
    done < <(${jq} -r -f ${pillFilter} --args ${providerArgs} < "$cache" 2>/dev/null)

    printf '%s' "$pills"
    if tmp="$(mktemp "$rendered.XXXXXX")"; then
      printf '%s\n%s\n' "$key" "$pills" > "$tmp" && mv "$tmp" "$rendered" || rm -f "$tmp"
    fi
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
