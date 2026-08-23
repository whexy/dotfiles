# SketchyBar quota pills (macOS).
#
# A hidden fetcher item refreshes the shared cache every 5 minutes; each
# pill polls it once a minute and renders the best account's binding
# window (see ./summary.jq). Clicking a pill opens a compact popup with
# each account's binding quota window.
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

  # Mirrors the bar-position logic in ../sketchybar.nix so popups open on
  # the screen-facing side of the bar.
  autoHideMenuBar = osConfig != null && (osConfig.dotfiles.hardware.display.autoHideMenuBar or true);
  barOnTop = autoHideMenuBar;

  aiQuota = "${perSystem.self.ai-quota}/bin/ai-quota";
  sketchybar = lib.getExe pkgs.sketchybar;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;
  cacheFile = "${config.xdg.cacheHome}/ai-quota.json";

  enabled =
    cfg.sketchybar.enable
    && pkgs.stdenv.hostPlatform.isDarwin
    && config.dotfiles.agents.enable
    && config.dotfiles.agents.enableProxyAccounts;

  # Gruvbox subset of the palette in ../sketchybar.nix.
  colors = {
    fg = "0xffebdbb2";
    gray = "0xffa89984";
    yellow = "0xffd79921";
    brightRed = "0xfffb4934";
    green = "0xffb8bb26";
    item = "0xff3c3836";
    itemAlt = "0xff504945";
  };

  mkPlugin = name: pkgs.writeShellScript "sketchybar-ai-quota-${name}";

  fetcherPlugin = mkPlugin "fetch" ''
    out="$(${aiQuota} --json 2>/dev/null)" || exit 0
    mkdir -p "$(dirname "${cacheFile}")"
    tmp="${cacheFile}.tmp.$$"
    printf '%s\n' "$out" > "$tmp"
    mv "$tmp" "${cacheFile}"
  '';

  pillPlugin =
    provider:
    mkPlugin "pill-${provider}" ''
      cache="${cacheFile}"
      [ -f "$cache" ] || exit 0

      summary="$(${jq} -c -f ${summaryFilter} --arg provider ${provider} "$cache" 2>/dev/null)" || exit 0

      if [ "$(printf '%s' "$summary" | ${jq} -r '.present')" != "true" ]; then
        ${sketchybar} --set "$NAME" drawing=off
        exit 0
      fi

      state="$(printf '%s' "$summary" | ${jq} -r 'if .present == true then .state else "error" end')"
      case "$state" in
        ok) color=${colors.green} ;;
        warning) color=${colors.yellow} ;;
        critical) color=${colors.brightRed} ;;
        *) color=${colors.gray} ;;
      esac

      label="$(printf '%s' "$summary" | ${jq} -r '.label // "--"')"
      ${sketchybar} --set "$NAME" drawing=on icon.color="$color" label="$label"
    '';

  popupPlugin =
    provider:
    mkPlugin "popup-${provider}" ''
      cache="${cacheFile}"
      details="ai_quota.${provider}.details"

      content=""
      color=${colors.gray}
      if [ -f "$cache" ]; then
        summary="$(${jq} -c -f ${summaryFilter} --arg provider ${provider} "$cache" 2>/dev/null)" || summary=""
        if [ -n "$summary" ]; then
          content="$(printf '%s' "$summary" | ${jq} -r '.compact_lines | join("\n")')"
          state="$(printf '%s' "$summary" | ${jq} -r 'if .present == true then .state else "error" end')"
          case "$state" in
            ok) color=${colors.green} ;;
            warning) color=${colors.yellow} ;;
            critical) color=${colors.brightRed} ;;
            *) color=${colors.gray} ;;
          esac
        fi
      fi
      [ -n "$content" ] || content="no quota data yet"

      ${sketchybar} --set "$details" label="$content" label.color="$color"
      ${sketchybar} --set "$NAME" popup.drawing=toggle
    '';

  fetcherItem = {
    name = "ai_quota.fetch";
    side = "right";
    settings = {
      drawing = "off";
      update_freq = 300;
      script = fetcherPlugin;
    };
  };

  # SketchyBar has no `popup.items` property; popup membership is expressed
  # by adding the item at the `popup.<parent>` position. Visibility follows
  # the popup, so the details item must not force drawing=off.
  mkDetailsItem = provider: {
    name = "ai_quota.${provider}.details";
    side = "popup.ai_quota.${provider}";
    settings = {
      "label.font" = "JetBrainsMono Nerd Font:Medium:11.0";
    };
  };

  mkPillItem = provider: icon: {
    name = "ai_quota.${provider}";
    side = "right";
    settings = {
      inherit icon;
      update_freq = 60;
      script = pillPlugin provider;
      "popup.horizontal" = "on";
      "popup.align" = "right";
      "popup.y_offset" = if barOnTop then "-8" else "8";
      "popup.background.color" = colors.itemAlt;
      "popup.background.corner_radius" = 10;
      "popup.background.border_width" = 0;
    };
    clickScript = "${popupPlugin provider}";
  };

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

  # Popup details items must be added after their host pill: sketchybar
  # rejects `popup.<parent>` positions for parents that don't exist yet.
  extraItems = [
    fetcherItem
  ]
  ++ map (p: mkPillItem p.name p.icon) providers
  ++ map mkDetailsItem (map (p: p.name) providers);
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.sketchybar.items = extraItems;
  };
}
