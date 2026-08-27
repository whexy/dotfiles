# SketchyBar quota pills (macOS).
#
# Each visible pill fetches current quota data on SketchyBar's own interval
# and renders its provider directly. Hovering opens a compact glass panel
# with one native progress meter per quota window.
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

  enabled =
    cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin && config.dotfiles.agents.enable;

  # Subset of the Liquid Glass palette in ../sketchybar.nix.
  colors = {
    fg = "0xffffffff";
    fgDim = "0xb3ffffff"; # 70% white, secondary popup text
    gray = "0xff98989d"; # systemGray, unknown state
    yellow = "0xffffd60a"; # systemYellow, quota warning
    red = "0xffff453a"; # systemRed, quota critical
    blue = "0xff0a84ff"; # systemBlue, kimi accent
    orange = "0xffff9f0a"; # systemOrange, codex accent
    green = "0xff30d158"; # systemGreen, OpenCode Go accent
    glass = "0x1affffff"; # 10% white, matching the bar capsules
    glassBorder = "0x40ffffff"; # 25% white hairline, popup edge highlight
    sliderTrack = "0x40ffffff"; # 25% white, reads on the glass capsule
  };

  mkPlugin = name: pkgs.writeShellScript "sketchybar-ai-quota-${name}";

  pillPlugin =
    provider: accent:
    mkPlugin "pill-${provider}" ''
      if [ "$SENDER" = "mouse.exited" ]; then
        ${sketchybar} --set "$NAME" popup.drawing=off
        exit 0
      fi

      raw="$(${aiQuota} --json 2>/dev/null)" || {
        ${sketchybar} --set "$NAME" icon.color=${colors.gray}
        exit 0
      }
      summary="$(printf '%s\n' "$raw" | ${jq} -c -f ${summaryFilter} --arg provider ${provider} 2>/dev/null)" || exit 0

      state="$(printf '%s' "$summary" | ${jq} -r 'if .present == true then .state else "error" end')"
      case "$state" in
        ok) color=${accent} ;;
        warning) color=${colors.yellow} ;;
        critical) color=${colors.red} ;;
        *) color=${colors.gray} ;;
      esac

      if [ "$SENDER" = "mouse.entered" ]; then
        for slot in ${lib.concatStringsSep " " (map toString popupSlots)}; do
          meter="ai_quota.${provider}.meter.$slot"
          meter_state="$(printf '%s' "$summary" | ${jq} -r --argjson index "$((slot - 1))" '.compact_meters[$index].state // empty')"
          if [ -n "$meter_state" ]; then
            meter_label="$(printf '%s' "$summary" | ${jq} -r --argjson index "$((slot - 1))" '.compact_meters[$index].label')"
            meter_remaining="$(printf '%s' "$summary" | ${jq} -r --argjson index "$((slot - 1))" '.compact_meters[$index].remaining | round')"
            meter_reset="$(printf '%s' "$summary" | ${jq} -r --argjson index "$((slot - 1))" '.compact_meters[$index].reset // "—"')"
            case "$meter_state" in
              ok) meter_color=${accent} ;;
              warning) meter_color=${colors.yellow} ;;
              critical) meter_color=${colors.red} ;;
              *) meter_color=${colors.gray} ;;
            esac
            ${sketchybar} --set "$meter" drawing=on \
              icon="$meter_label" \
              label="''${meter_remaining}%  ·  ''${meter_reset}" \
              slider.percentage="$meter_remaining" \
              slider.highlight_color="$meter_color"
          else
            ${sketchybar} --set "$meter" drawing=off
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

  popupSlots = lib.range 1 4;

  # A popup slider is a native progress meter: the icon names the window, the
  # center bar shows remaining quota, and the label gives the exact value and
  # reset countdown. Unused slots stay hidden.
  mkMeterItem = provider: slot: {
    name = "ai_quota.${provider}.meter.${toString slot}";
    kind = "slider";
    width = 112;
    side = "popup.ai_quota.${provider}";
    settings = {
      drawing = "off";
      padding_left = 8;
      padding_right = 8;
      icon = "";
      "icon.font" = ".AppleSystemUIFont:Semibold:11.5";
      "icon.color" = colors.fg;
      "icon.width" = 60;
      "icon.align" = "left";
      "icon.padding_left" = 8;
      "icon.padding_right" = 8;
      label = "";
      "label.font" = ".AppleSystemUIFont:Medium:11.5";
      "label.color" = colors.fgDim;
      "label.width" = 116;
      "label.align" = "right";
      "label.padding_left" = 14;
      "label.padding_right" = 10;
      "slider.background.color" = colors.sliderTrack;
      "slider.background.height" = 6;
      "slider.background.corner_radius" = 3;
      "slider.knob" = "";
      "background.drawing" = "on";
      "background.color" = colors.glass;
      "background.height" = 30;
      "background.corner_radius" = 15;
      "background.border_width" = 1;
      "background.border_color" = colors.glassBorder;
    };
  };

  mkPillItem =
    provider:
    {
      logo,
      logoScale,
      accent,
      ...
    }:
    {
      name = "ai_quota.${provider}";
      kind = "slider";
      width = 24;
      side = "left";
      settings = {
        icon = " ";
        updates = "on";
        update_freq = 60;
        script = pillPlugin provider accent;
        # The image padding positions the logo; the fixed icon width must also
        # include that padding so the background image cannot reach the slider.
        "icon.width" = 28;
        "icon.padding_left" = 0;
        "icon.padding_right" = 0;
        "icon.background.drawing" = "on";
        "icon.background.image" = logo;
        "icon.background.image.scale" = logoScale;
        "icon.background.image.padding_left" = 7;
        "icon.background.image.padding_right" = 6;
        "slider.background.color" = colors.sliderTrack;
        "slider.background.height" = 4;
        "slider.background.corner_radius" = 2;
        "slider.knob" = "";
        "popup.horizontal" = "off";
        "popup.align" = "left";
        "popup.y_offset" = if barOnTop then "-8" else "8";
        "popup.height" = 38;
        "popup.blur_radius" = 0;
        "popup.background.drawing" = "off";
      };
      subscribe = [
        "mouse.entered"
        "mouse.exited"
      ];
    };

  providers = [
    {
      name = "kimi";
      logo = ./logos/kimi.png;
      logoScale = 0.025;
      accent = colors.blue;
    }
    {
      name = "codex";
      logo = ./logos/codex.png;
      logoScale = 0.027;
      accent = colors.orange;
    }
    {
      name = "opencode-go";
      logo = ./logos/opencode-go.png;
      logoScale = 0.025;
      accent = colors.green;
    }
  ];

  # Popup details items must be added after their host pill: sketchybar
  # rejects `popup.<parent>` positions for parents that don't exist yet.
  extraItems =
    map (p: mkPillItem p.name p) providers
    ++ lib.concatMap (p: map (mkMeterItem p.name) popupSlots) providers;
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.sketchybar.items = extraItems;
  };
}
