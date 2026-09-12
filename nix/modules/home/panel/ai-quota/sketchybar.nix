# SketchyBar quota pills (macOS).
#
# Each provider is one Liquid Glass capsule with stacked, read-only quota
# tracks. The shortest window is on top; weekly and monthly windows follow.
# When countdown display is enabled, the reset time is shown on the right.
#
# Every item a refresh can touch is declared up front, and a refresh only
# flips properties in a single message. Adding an item rebuilds its window and
# restacks the bar, and each `sketchybar` invocation ends in a repaint, so
# removing and re-adding the tracks painted one empty frame per refresh.
# SketchyBar drops property writes that do not change a value, so unchanged
# quotas now repaint nothing at all.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;
  showCountdown = cfg.aiQuota.showCountdown;
  osConfig = args.osConfig or null;
  barOnTop = osConfig != null && (osConfig.dotfiles.hardware.display.autoHideMenuBar or true);

  shared = import ./shared.nix;
  inherit (shared) apiUrl updateInterval;

  curl = lib.getExe pkgs.curl;
  sketchybar = lib.getExe pkgs.sketchybar;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;
  cacheFile = "${config.xdg.cacheHome}/ai-quota.json";

  enabled =
    cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin && config.dotfiles.agents.enable;

  colors = {
    fg = "0xffffffff";
    gray = "0xff98989d";
    blue = "0xff007cff";
    orange = "0xffd97757";
    green = "0xff10a37f";
    white = "0xffffffff";
    track = "0x26ffffff";
    glass = "0x1affffff";
    glassBorder = "0x40ffffff";
    popup = "0xe6121d2c";
    popupBorder = "0x59ffffff";
  };

  mkPlugin = name: pkgs.writeShellScript "sketchybar-ai-quota-${name}";

  # A window further from binding is drawn fainter than the binding one.
  dim = alpha: accent: "0x${alpha}${lib.removePrefix "0xff" accent}";

  # The item pool is preallocated, so accounts and windows past these bounds
  # are not rendered; summary.jq already caps each account at three windows.
  maxColumns = 3;
  maxRows = 3;
  maxPopupMeters = maxColumns * maxRows;

  fetchPlugin = mkPlugin "fetch" ''
    out="$(${curl} -fsS --max-time 10 ${lib.escapeShellArg apiUrl} 2>/dev/null)" || exit 0
    printf '%s\n' "$out" | ${jq} -e '.providers | arrays' >/dev/null 2>&1 || exit 0
    mkdir -p ${lib.escapeShellArg (builtins.dirOf cacheFile)}
    tmp="${cacheFile}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    printf '%s\n' "$out" > "$tmp"
    mv "$tmp" ${lib.escapeShellArg cacheFile}
    trap - EXIT
    ${sketchybar} --trigger ai_quota_refresh
  '';

  togglePlugin =
    provider:
    mkPlugin "toggle-${provider}" ''
      # Restore cached values first in case a native slider consumed the click,
      # then toggle the details immediately while a forced refresh runs.
      ${sketchybar} --trigger ai_quota_refresh \
        --set ai_quota.${provider}.icon popup.drawing=toggle
      ${fetchPlugin} >/dev/null 2>&1 &
    '';

  pillPlugin =
    provider: accent:
    mkPlugin "pill-${provider}" ''
      [ -f ${lib.escapeShellArg cacheFile} ] || exit 0
      summary="$(${jq} -c -f ${summaryFilter} --arg provider ${lib.escapeShellArg provider} ${lib.escapeShellArg cacheFile} 2>/dev/null)" || exit 0

      if [ "$(printf '%s' "$summary" | ${jq} -r '.present')" != "true" ]; then
        hide_args=(
          --set '/ai_quota\.${provider}\.lane\..*/' drawing=off
          --set '/ai_quota\.${provider}\.popup\.meter\..*/' drawing=off
          --set ai_quota.${provider}.icon drawing=off popup.drawing=off
          --set ai_quota.${provider}.glass background.drawing=off
          --set ai_quota.${provider}.slot drawing=off
          ${lib.optionalString showCountdown "--set ai_quota.${provider}.countdown drawing=off"}
          --set ai_quota.${provider}.popup.header drawing=off
        )
        ${sketchybar} "''${hide_args[@]}"
        exit 0
      fi

      ${lib.optionalString showCountdown ''
        countdown="$(printf '%s' "$summary" | ${jq} -r '.display_meter.countdown // "—"')"
      ''}
      args=(
        --set ai_quota.${provider}.glass background.drawing=on
        --set ai_quota.${provider}.icon drawing=on
        --set ai_quota.${provider}.slot drawing=on
        --set ai_quota.${provider}.popup.header drawing=on
        ${lib.optionalString showCountdown ''--set ai_quota.${provider}.countdown drawing=on label="$countdown"''}
      )

      # Zero-width sliders share the reserved track slot. Right padding offsets
      # each account column without changing the capsule's layout width.
      while IFS=$'\t' read -r column row columns rows used remaining span; do
        lane="ai_quota.${provider}.lane.$column.$row"
        if [ "$used" != 1 ]; then
          args+=(--set "$lane" drawing=off)
          continue
        fi
        column_width=$(((${toString trackWidth} - 2 * (columns - 1)) / columns))
        [ "$column_width" -ge 1 ] || column_width=1
        case "$rows:$row" in
          2:0) lane_y=4 ;; 2:1) lane_y=-4 ;;
          3:0) lane_y=6 ;; 3:1) lane_y=0 ;; 3:2) lane_y=-6 ;;
          *) lane_y=0 ;;
        esac
        lane_color=${accent}
        if [ "$span" -ge 2592000 ]; then
          lane_color=${dim "66" accent}
        elif [ "$span" -ge 604800 ]; then
          lane_color=${dim "aa" accent}
        fi
        offset=$(( ${toString laneRightPadding} + (columns - column - 1) * (column_width + 2) ))
        args+=(--set "$lane" drawing=on slider.width="$column_width"
          padding_right="$offset" y_offset="$lane_y"
          slider.percentage="$remaining" slider.highlight_color="$lane_color")
      done < <(printf '%s' "$summary" | ${jq} -r '
        (.columns[:${toString maxColumns}]) as $columns
        | ($columns | length) as $count
        | range(0; ${toString maxColumns}) as $column
        | (($columns[$column].meters // [])[:${toString maxRows}]) as $meters
        | ($meters | length) as $rows
        | range(0; ${toString maxRows}) as $row
        | ($meters[$row] // null) as $meter
        | [$column, $row, $count, $rows,
           (if $meter == null then 0 else 1 end),
           (if $meter == null then 0 else ($meter.remaining | round) end),
           (if $meter == null then 0 else $meter.span end)] | @tsv')

      while IFS=$'\t' read -r slot used meter_label meter_remaining meter_reset; do
        popup_meter="ai_quota.${provider}.popup.meter.$slot"
        if [ "$used" != 1 ]; then
          args+=(--set "$popup_meter" drawing=off)
          continue
        fi
        args+=(--set "$popup_meter" drawing=on icon="$meter_label"
          label="''${meter_remaining}% · ''${meter_reset}"
          slider.percentage="$meter_remaining")
      done < <(printf '%s' "$summary" | ${jq} -r '
        .detail_meters as $meters
        | range(0; ${toString maxPopupMeters}) as $slot
        | ($meters[$slot] // null) as $meter
        | [$slot,
           (if $meter == null then 0 else 1 end),
           (if $meter == null then "" else ($meter.account + " · " + $meter.label) end),
           (if $meter == null then 0 else ($meter.remaining | round) end),
           (if $meter == null then "—" else ($meter.reset // "—") end)] | @tsv')

      ${sketchybar} "''${args[@]}"
    '';

  fetcherItem = {
    name = "ai_quota.fetch";
    side = "right";
    settings = {
      drawing = "off";
      updates = "on";
      update_freq = updateInterval;
      script = fetchPlugin;
    };
  };

  mkIconItem =
    provider:
    {
      logo,
      logoScale,
      accent,
      ...
    }:
    {
      name = "ai_quota.${provider}.icon";
      side = "right";
      settings = {
        drawing = "off";
        updates = "on";
        script = pillPlugin provider accent;
        icon = " ";
        "icon.width" = 28;
        "icon.padding_left" = 0;
        "icon.padding_right" = 0;
        "icon.background.drawing" = "on";
        "icon.background.image" = logo;
        "icon.background.image.scale" = logoScale;
        "icon.background.image.padding_left" = 7;
        "icon.background.image.padding_right" = 5;
        label = "";
        "label.drawing" = "off";
        "background.drawing" = "off";
        "popup.horizontal" = "off";
        "popup.align" = "right";
        "popup.y_offset" = if barOnTop then "-8" else "8";
        "popup.height" = 34;
        "popup.blur_radius" = 28;
        "popup.background.drawing" = "on";
        "popup.background.color" = colors.popup;
        "popup.background.corner_radius" = 14;
        "popup.background.border_width" = 1;
        "popup.background.border_color" = colors.popupBorder;
      };
      clickScript = toString (togglePlugin provider);
      subscribe = [ "ai_quota_refresh" ];
    };

  trackWidth = 42;
  rightPadding = 8;

  # A lane paints its track leftwards from its own right edge, so the trailing
  # gap has to come from the lane's own right padding; a wider `slot` would
  # only pad the side away from the capsule edge. The countdown label already
  # supplies that gap when it is drawn.
  laneRightPadding = if showCountdown then 0 else rightPadding;

  # One slider per (account column, window row) the pill can ever show. Each
  # starts hidden and is only revealed for the slots a refresh actually fills.
  mkLaneItems =
    provider: accent:
    lib.concatMap (
      column:
      map (row: {
        name = "ai_quota.${provider}.lane.${toString column}.${toString row}";
        kind = "slider";
        width = trackWidth;
        side = "right";
        settings = {
          drawing = "off";
          width = 0;
          padding_left = 0;
          padding_right = laneRightPadding;
          "slider.highlight_color" = accent;
          "slider.background.color" = colors.track;
          "slider.background.height" = 4;
          "slider.background.corner_radius" = 2;
          "slider.knob.drawing" = "off";
          "icon.drawing" = "off";
          "label.drawing" = "off";
          "background.drawing" = "off";
        };
        clickScript = toString (togglePlugin provider);
      }) (lib.range 0 (maxRows - 1))
    ) (lib.range 0 (maxColumns - 1));

  mkPopupMeterItems =
    provider: accent:
    map (slot: {
      name = "ai_quota.${provider}.popup.meter.${toString slot}";
      kind = "slider";
      width = 118;
      side = "popup.ai_quota.${provider}.icon";
      settings = {
        drawing = "off";
        padding_left = 8;
        padding_right = 8;
        "icon.font" = ".AppleSystemUIFont:Semibold:11.5";
        "icon.color" = accent;
        "label.font" = ".AppleSystemUIFont:Medium:11.5";
        "label.color" = colors.fg;
        "slider.highlight_color" = accent;
        "slider.background.color" = colors.track;
        "slider.background.height" = 6;
        "slider.background.corner_radius" = 3;
        "slider.knob.drawing" = "off";
        "background.drawing" = "off";
      };
      clickScript = "${sketchybar} --trigger ai_quota_refresh";
    }) (lib.range 0 (maxPopupMeters - 1));

  mkSlotItem = provider: {
    name = "ai_quota.${provider}.slot";
    side = "right";
    settings = {
      drawing = "off";
      width = trackWidth;
      padding_left = 0;
      padding_right = 0;
      icon = "";
      "icon.drawing" = "off";
      label = "";
      "label.drawing" = "off";
      "background.drawing" = "off";
    };
    clickScript = toString (togglePlugin provider);
  };

  mkCountdownItem = provider: accent: {
    name = "ai_quota.${provider}.countdown";
    side = "right";
    settings = {
      drawing = "off";
      icon = "";
      "icon.drawing" = "off";
      label = "—";
      "label.color" = accent;
      "label.font" = ".AppleSystemUIFont:Medium:11.5";
      "label.width" = 44;
      "label.align" = "center";
      "label.padding_left" = 6;
      "label.padding_right" = 8;
      "background.drawing" = "off";
    };
    clickScript = toString (togglePlugin provider);
  };

  mkPopupHeaderItem =
    provider:
    {
      logo,
      logoScale,
      title,
      ...
    }:
    {
      name = "ai_quota.${provider}.popup.header";
      side = "popup.ai_quota.${provider}.icon";
      settings = {
        drawing = "off";
        icon = " ";
        "icon.width" = 28;
        "icon.padding_left" = 0;
        "icon.padding_right" = 0;
        "icon.background.drawing" = "on";
        "icon.background.image" = logo;
        "icon.background.image.scale" = logoScale;
        "icon.background.image.padding_left" = 7;
        "icon.background.image.padding_right" = 5;
        label = title;
        "label.font" = ".AppleSystemUIFont:Semibold:12.5";
        "label.color" = colors.fg;
        "label.padding_left" = 3;
        "label.padding_right" = 10;
        "background.drawing" = "off";
      };
    };

  providers = [
    {
      name = "claude";
      title = "Claude";
      logo = ./logos/claude.png;
      logoScale = 0.026;
      accent = colors.orange;
    }
    {
      name = "codex";
      title = "Codex";
      logo = ./logos/codex.png;
      logoScale = 0.027;
      accent = colors.green;
    }
    {
      name = "kimi";
      title = "Kimi";
      logo = ./logos/kimi.png;
      logoScale = 0.025;
      accent = colors.blue;
    }
    {
      name = "antigravity";
      title = "Antigravity";
      logo = ./logos/antigravity.png;
      logoScale = 0.026;
      accent = colors.gray;
    }
    {
      name = "grok";
      title = "Grok";
      logo = ./logos/grok.png;
      logoScale = 0.026;
      accent = colors.white;
    }
  ];

  # Right-side items stack from the right edge inwards, so a pill's parts are
  # added in reverse of their visual order. Sliders are the exception: they
  # paint their track in the layout flow direction, which runs leftwards here,
  # so each lane must precede the `slot` whose width reserves the track's space
  # rather than follow the icon it would otherwise paint over.
  providerItems =
    p:
    lib.optional showCountdown (mkCountdownItem p.name p.accent)
    # Sliders paint their track in the layout flow direction, so every lane is
    # declared before the `slot` that reserves its space.
    ++ mkLaneItems p.name p.accent
    ++ [
      (mkSlotItem p.name)
      (mkIconItem p.name p)
    ]
    ++ [ (mkPopupHeaderItem p.name p) ]
    ++ mkPopupMeterItems p.name p.accent;

  providerBracket = p: {
    name = "ai_quota.${p.name}.glass";
    members = [
      "ai_quota.${p.name}.icon"
      "ai_quota.${p.name}.slot"
    ]
    ++ lib.optional showCountdown "ai_quota.${p.name}.countdown";
    settings = {
      "background.drawing" = "on";
      "background.color" = colors.glass;
      "background.height" = 26;
      "background.corner_radius" = 13;
      "background.border_width" = 1;
      "background.border_color" = colors.glassBorder;
    };
  };
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.sketchybar = {
      events = [ "ai_quota_refresh" ];
      # mkAfter keeps the quota pills to the left of the other right-side
      # pills (renpho, battery, clock) regardless of module import order.
      items = lib.mkAfter ([ fetcherItem ] ++ lib.concatMap providerItems (lib.reverseList providers));
      brackets = map providerBracket providers;
    };
  };
}
