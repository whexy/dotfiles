# Renpho weight pill for SketchyBar (macOS).
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  hcfg = config.services.renpho-health;

  autoHideMenuBar = osConfig != null && (osConfig.dotfiles.hardware.display.autoHideMenuBar or true);
  barOnTop = autoHideMenuBar;

  sketchybar = lib.getExe pkgs.sketchybar;
  jq = lib.getExe pkgs.jq;
  summaryFilter = ./summary.jq;
  summaryCount = 5;
  staleAfter = 36 * 60 * 60;

  enabled = cfg.renpho.enable && cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin;

  colors = {
    gray = "0xffa89984";
    brightRed = "0xfffb4934";
    green = "0xffb8bb26";
    purple = "0xffd3869b";
    itemAlt = "0xff504945";
  };

  popupSlots = lib.range 1 summaryCount;

  pillPlugin = pkgs.writeShellScript "sketchybar-renpho" ''
    cache=${lib.escapeShellArg hcfg.cachePath}

    if [ "$SENDER" = "mouse.exited" ]; then
      ${sketchybar} --set "$NAME" popup.drawing=off
      exit 0
    fi

    if [ ! -f "$cache" ]; then
      ${sketchybar} --set "$NAME" icon.color=${colors.gray} label="…"
      exit 0
    fi

    summary="$(${jq} -c --argjson summary_count ${toString summaryCount} -f ${summaryFilter} "$cache" 2>/dev/null)" || exit 0
    modified="$(${pkgs.coreutils}/bin/stat -c %Y "$cache" 2>/dev/null || printf 0)"
    now="$(${pkgs.coreutils}/bin/date +%s)"
    age=$((now - modified))

    state="$(printf '%s' "$summary" | ${jq} -r '.state')"
    if [ "$age" -gt ${toString staleAfter} ]; then
      state=stale
    fi

    case "$state" in
      down) color=${colors.green} ;;
      up) color=${colors.brightRed} ;;
      stale) color=${colors.gray} ;;
      *) color=${colors.purple} ;;
    esac

    if [ "$SENDER" = "mouse.entered" ]; then
      for slot in ${lib.concatStringsSep " " (map toString popupSlots)}; do
        details="renpho.details.$slot"
        content="$(printf '%s' "$summary" | ${jq} -r --argjson index "$((slot - 1))" '.lines[$index] // empty')"
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
      ${sketchybar} --set "$NAME" icon.color=${colors.gray} label="…"
      exit 0
    fi

    label="$(printf '%s' "$summary" | ${jq} -r '
      (if (.weight | type) == "number" then (.weight * 10 | round / 10 | tostring) + "kg" else "?" end)
      + (if .trend == "" then "" elif .delta == null then " " + .trend else " " + .trend + (.delta | tostring) end)
    ')"

    ${sketchybar} --set "$NAME" drawing=on icon.color="$color" label="$label"
  '';

  pillItem = {
    name = "renpho";
    side = "right";
    settings = {
      icon = "󰓅";
      "icon.color" = colors.purple;
      update_freq = 60;
      script = pillPlugin;
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
      "system_woke"
    ];
  };

  mkDetailsItem = slot: {
    name = "renpho.details.${toString slot}";
    side = "popup.renpho";
    settings = {
      drawing = "off";
      "label.font" = "JetBrainsMono Nerd Font:Medium:11.0";
    };
  };
in
{
  config = lib.mkIf enabled {
    dotfiles.panel.sketchybar.items = [ pillItem ] ++ map mkDetailsItem popupSlots;
  };
}
