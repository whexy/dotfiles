# SketchyBar quota pills (macOS).
#
# Each provider is one Liquid Glass capsule with stacked, read-only quota
# tracks. The shortest window is on top; weekly and monthly windows follow.
# When countdown display is enabled, the reset time is shown on the right.
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
    track = "0x26ffffff";
    glass = "0x1affffff";
    glassBorder = "0x40ffffff";
    popup = "0xe6121d2c";
    popupBorder = "0x59ffffff";
  };

  mkPlugin = name: pkgs.writeShellScript "sketchybar-ai-quota-${name}";

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
      ${sketchybar} --trigger ai_quota_refresh
      ${sketchybar} --set ai_quota.${provider}.icon popup.drawing=toggle
      ${fetchPlugin} >/dev/null 2>&1 &
    '';

  pillPlugin =
    provider: accent:
    mkPlugin "pill-${provider}" ''
      [ -f ${lib.escapeShellArg cacheFile} ] || exit 0
      summary="$(${jq} -c -f ${summaryFilter} --arg provider ${lib.escapeShellArg provider} ${lib.escapeShellArg cacheFile} 2>/dev/null)" || exit 0

      if [ "$(printf '%s' "$summary" | ${jq} -r '.present')" != "true" ]; then
        hide_args=(
          --set ai_quota.${provider}.icon drawing=off popup.drawing=off
          --set ai_quota.${provider}.glass background.drawing=off
          --set ai_quota.${provider}.lane.1 drawing=off
          --set ai_quota.${provider}.lane.2 drawing=off
          --set ai_quota.${provider}.lane.3 drawing=off
          --set ai_quota.${provider}.slot drawing=off
          ${lib.optionalString showCountdown "--set ai_quota.${provider}.countdown drawing=off"}
          --set ai_quota.${provider}.popup.header drawing=off
          --set ai_quota.${provider}.popup.meter.1 drawing=off
          --set ai_quota.${provider}.popup.meter.2 drawing=off
          --set ai_quota.${provider}.popup.meter.3 drawing=off
        )
        ${sketchybar} "''${hide_args[@]}"
        exit 0
      fi

      ${lib.optionalString showCountdown ''
        countdown="$(printf '%s' "$summary" | ${jq} -r '.display_meter.countdown // "—"')"
      ''}
      color=${accent}

      args=(
        --set ai_quota.${provider}.glass background.drawing=on
        --set ai_quota.${provider}.icon drawing=on
        --set ai_quota.${provider}.slot drawing=on
        ${lib.optionalString showCountdown ''--set ai_quota.${provider}.countdown drawing=on label="$countdown" label.color="$color"''}
      )
      lane_count="$(printf '%s' "$summary" | ${jq} -r '[.compact_meters[:3][]] | length')"
      for slot in 1 2 3; do
        meter_index=$((slot - 1))
        lane="ai_quota.${provider}.lane.$slot"
        remaining="$(printf '%s' "$summary" | ${jq} -r --argjson index "$meter_index" '.compact_meters[$index].remaining // empty | round')"
        if [ -n "$remaining" ]; then
          case "$lane_count:$slot" in
            1:1) lane_y=0 ;;
            2:1) lane_y=4 ;;
            2:2) lane_y=-4 ;;
            3:1) lane_y=6 ;;
            3:2) lane_y=0 ;;
            3:3) lane_y=-6 ;;
            *) lane_y=0 ;;
          esac
          args+=(
            --set "$lane"
            drawing=on
            y_offset="$lane_y"
            slider.percentage="$remaining"
            slider.highlight_color="$color"
          )
        else
          args+=(--set "$lane" drawing=off)
        fi
      done

      args+=(--set ai_quota.${provider}.popup.header drawing=on)
      for slot in 1 2 3; do
        meter_index=$((slot - 1))
        popup_meter="ai_quota.${provider}.popup.meter.$slot"
        meter_label="$(printf '%s' "$summary" | ${jq} -r --argjson index "$meter_index" '.compact_meters[$index].label // empty')"
        meter_remaining="$(printf '%s' "$summary" | ${jq} -r --argjson index "$meter_index" '.compact_meters[$index].remaining // empty | round')"
        meter_reset="$(printf '%s' "$summary" | ${jq} -r --argjson index "$meter_index" '.compact_meters[$index].reset // "—"')"
        if [ -n "$meter_remaining" ]; then
          meter_color=${accent}
          args+=(
            --set "$popup_meter"
            drawing=on
            icon="$meter_label"
            label="''${meter_remaining}% · ''${meter_reset}"
            slider.percentage="$meter_remaining"
            slider.highlight_color="$meter_color"
            icon.color="$meter_color"
          )
        else
          args+=(--set "$popup_meter" drawing=off)
        fi
      done
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

  mkLaneItem = provider: slot: {
    name = "ai_quota.${provider}.lane.${toString slot}";
    kind = "slider";
    width = trackWidth;
    side = "right";
    settings = {
      drawing = "off";
      width = 0;
      padding_left = 0;
      padding_right = laneRightPadding;
      y_offset = 0;
      "slider.background.color" = colors.track;
      "slider.background.height" = 4;
      "slider.background.corner_radius" = 2;
      "slider.knob.drawing" = "off";
      icon = "";
      "icon.drawing" = "off";
      label = "";
      "label.drawing" = "off";
      "background.drawing" = "off";
    };
    clickScript = toString (togglePlugin provider);
  };

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

  mkCountdownItem = provider: {
    name = "ai_quota.${provider}.countdown";
    side = "right";
    settings = {
      drawing = "off";
      icon = "";
      "icon.drawing" = "off";
      label = "—";
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

  mkPopupMeterItem = provider: slot: {
    name = "ai_quota.${provider}.popup.meter.${toString slot}";
    kind = "slider";
    width = 118;
    side = "popup.ai_quota.${provider}.icon";
    settings = {
      drawing = "off";
      padding_left = 8;
      padding_right = 8;
      icon = "";
      "icon.font" = ".AppleSystemUIFont:Semibold:11.5";
      "icon.color" = colors.fg;
      "icon.width" = 56;
      "icon.align" = "left";
      "icon.padding_left" = 4;
      "icon.padding_right" = 8;
      label = "";
      "label.font" = ".AppleSystemUIFont:Medium:11.5";
      "label.color" = colors.fg;
      "label.width" = 94;
      "label.align" = "right";
      "label.padding_left" = 10;
      "label.padding_right" = 6;
      "slider.background.color" = colors.track;
      "slider.background.height" = 6;
      "slider.background.corner_radius" = 3;
      "slider.knob.drawing" = "off";
      "background.drawing" = "off";
    };
    # Popup meters are informational too; undo SketchyBar's native slider
    # click before the temporary value can be mistaken for quota data.
    clickScript = "${sketchybar} --trigger ai_quota_refresh";
  };

  # Listed left-to-right as they should appear on the bar; the render order is
  # reversed below because SketchyBar stacks right-side items from the right
  # edge inwards.
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
  ];

  # Right-side items stack from the right edge inwards, so a pill's parts are
  # added in reverse of their visual order. Sliders are the exception: they
  # paint their track in the layout flow direction, which runs leftwards here,
  # so each lane must precede the `slot` whose width reserves the track's space
  # rather than follow the icon it would otherwise paint over.
  providerItems =
    p:
    lib.optional showCountdown (mkCountdownItem p.name)
    ++ [
      (mkLaneItem p.name 1)
      (mkLaneItem p.name 2)
      (mkLaneItem p.name 3)
      (mkSlotItem p.name)
      (mkIconItem p.name p)
    ]
    ++ [
      (mkPopupHeaderItem p.name p)
      (mkPopupMeterItem p.name 1)
      (mkPopupMeterItem p.name 2)
      (mkPopupMeterItem p.name 3)
    ];

  providerBracket = p: {
    name = "ai_quota.${p.name}.glass";
    members = [
      "ai_quota.${p.name}.icon"
      "ai_quota.${p.name}.lane.1"
      "ai_quota.${p.name}.lane.2"
      "ai_quota.${p.name}.lane.3"
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
