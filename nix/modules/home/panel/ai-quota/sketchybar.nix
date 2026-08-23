# SketchyBar quota pills (macOS).
#
# A hidden fetcher item refreshes the shared cache every 5 minutes; each
# slider polls it once a minute and renders the best account's remaining
# quota (see ./summary.jq). Hovering it opens a compact vertical popup with
# one quota window per line.
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

      if [ "$SENDER" = "mouse.exited" ]; then
        ${sketchybar} --set "$NAME" popup.drawing=off
        exit 0
      fi

      [ -f "$cache" ] || exit 0
      summary="$(${jq} -c -f ${summaryFilter} --arg provider ${provider} "$cache" 2>/dev/null)" || exit 0

      state="$(printf '%s' "$summary" | ${jq} -r 'if .present == true then .state else "error" end')"
      case "$state" in
        ok) color=${colors.green} ;;
        warning) color=${colors.yellow} ;;
        critical) color=${colors.brightRed} ;;
        *) color=${colors.gray} ;;
      esac

      if [ "$SENDER" = "mouse.entered" ]; then
        for slot in ${lib.concatStringsSep " " (map toString popupSlots)}; do
          details="ai_quota.${provider}.details.$slot"
          content="$(printf '%s' "$summary" | ${jq} -r --argjson index "$((slot - 1))" '.compact_lines[$index] // empty')"
          if [ -n "$content" ]; then
            ${sketchybar} --set "$details" drawing=on label="$content" label.color="$color"
          else
            ${sketchybar} --set "$details" drawing=off
          fi
        done
        ${sketchybar} --set "$NAME" popup.drawing=on
        exit 0
      fi

      if [ "$(printf '%s' "$summary" | ${jq} -r '.present')" != "true" ]; then
        ${sketchybar} --set "$NAME" drawing=off
        exit 0
      fi

      remaining="$(printf '%s' "$summary" | ${jq} -r '.remaining // 0 | round')"
      ${sketchybar} --set "$NAME" drawing=on \
        icon.color="$color" \
        label="''${remaining}%" \
        slider.percentage="$remaining" \
        slider.highlight_color="$color"
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

  popupSlots = lib.range 1 4;

  # Newlines in an item label are rendered horizontally, so each quota window
  # gets its own popup item. Unused slots stay hidden.
  mkDetailsItem = provider: slot: {
    name = "ai_quota.${provider}.details.${toString slot}";
    side = "popup.ai_quota.${provider}";
    settings = {
      drawing = "off";
      "label.font" = "JetBrainsMono Nerd Font:Medium:11.0";
    };
  };

  mkPillItem = provider: icon: {
    name = "ai_quota.${provider}";
    kind = "slider";
    width = 38;
    side = "right";
    settings = {
      inherit icon;
      update_freq = 60;
      script = pillPlugin provider;
      "slider.background.color" = colors.gray;
      "slider.background.height" = 4;
      "slider.background.corner_radius" = 2;
      "slider.knob" = "";
      "popup.horizontal" = "off";
      "popup.align" = "right";
      "popup.y_offset" = if barOnTop then "-8" else "8";
      "popup.background.color" = colors.itemAlt;
      "popup.background.corner_radius" = 10;
      "popup.background.border_width" = 0;
    };
    subscribe = [
      "mouse.entered"
      "mouse.exited"
    ];
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
  ++ lib.concatMap (p: map (mkDetailsItem p.name) popupSlots) providers;
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.sketchybar.items = extraItems;
  };
}
