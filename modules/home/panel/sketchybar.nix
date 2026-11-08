# SketchyBar status bar configuration (macOS)
#
# This file owns the bar itself: appearance, the item renderer, and the
# built-in right-side pills. Feature modules contribute items through
# `dotfiles.panel.sketchybar.items` and custom events through
# `dotfiles.panel.sketchybar.events` (see ./wm and ./ai-quota).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;
  style = import ./sketchybar-style.nix { inherit config; };
  inherit (style) colors capsule;

  sketchybar = lib.getExe pkgs.sketchybar;

  mkPlugin = name: pkgs.writeShellScript "sketchybar-${name}";

  clockPlugin = mkPlugin "clock" ''
    ${sketchybar} --set "$NAME" label="$(/bin/date '+%b %d %H:%M')"
  '';

  batteryPlugin = mkPlugin "battery" ''
    battery="$(/usr/bin/pmset -g batt)"
    percentage="$(printf '%s\n' "$battery" | /usr/bin/grep -Eo '[0-9]+%' | /usr/bin/head -n 1 | /usr/bin/tr -d '%')"

    if [ -z "$percentage" ]; then
      ${sketchybar} --set "$NAME" drawing=off
      exit 0
    fi

    if printf '%s\n' "$battery" | /usr/bin/grep -q 'AC Power'; then
      icon="󰂄"
      color=${colors.green}
    elif [ "$percentage" -le 15 ]; then
      icon="󰂃"
      color=${colors.red}
    elif [ "$percentage" -le 30 ]; then
      icon="󰁻"
      color=${colors.yellow}
    elif [ "$percentage" -le 60 ]; then
      icon="󰁾"
      color=${colors.fg}
    else
      icon="󰁹"
      color=${colors.fg}
    fi

    ${sketchybar} --set "$NAME" drawing=on icon="$icon" icon.color="$color" label="$percentage%"
  '';

  # ---------------------------------------------------------------------------
  # Bar items, declared as data and rendered below.
  # ---------------------------------------------------------------------------

  # SketchyBar lays right-side items out right-to-left in the order they are
  # added, so these two anchor the far right and every contributed right-side
  # item lands to their left.
  baseItems = [
    {
      name = "clock";
      side = "right";
      settings = {
        icon = "󰥔";
        update_freq = 15;
        script = clockPlugin;
      };
      clickScript = "/usr/bin/open -a Calendar";
    }
    {
      name = "battery";
      side = "right";
      settings = {
        update_freq = 60;
        script = batteryPlugin;
      };
      clickScript = "/usr/bin/open x-apple.systempreferences:com.apple.Battery-Settings.extension";
      subscribe = [
        "system_woke"
        "power_source_change"
      ];
    }
  ];

  allItems = baseItems ++ cfg.sketchybar.items;

  renderItem =
    item:
    let
      settings = lib.concatStringsSep " " (
        lib.mapAttrsToList (k: v: ''${k}="${toString v}"'') item.settings
      );
      click = lib.optionalString (
        (item.clickScript or null) != null
      ) " click_script=\"${item.clickScript}\"";
      subscribed = item.subscribe or [ ];
      events = lib.optionalString (
        subscribed != [ ]
      ) " --subscribe ${item.name} ${lib.concatStringsSep " " subscribed}";
      add =
        if (item.kind or "item") == "slider" then
          "--add slider ${item.name} ${item.side} ${toString item.width}"
        else
          "--add item ${item.name} ${item.side}";
    in
    ''
      ${sketchybar} ${add} \
        --set ${item.name} ${settings}${click}${events}
    '';

  renderBracket =
    bracket:
    let
      settings = lib.concatStringsSep " " (
        lib.mapAttrsToList (k: v: ''${k}="${toString v}"'') bracket.settings
      );
    in
    ''
      ${sketchybar} --add bracket ${bracket.name} ${lib.concatStringsSep " " bracket.members} \
        --set ${bracket.name} ${settings}
    '';

  sketchybarConfig = pkgs.writeShellScript "sketchybarrc" ''
    bar=(
      position=${cfg.sketchybar.position}
      height=36
      color=${colors.bar}
      margin=0
      y_offset=0
      corner_radius=0
      border_width=0
      shadow=off
      sticky=on
      topmost=window
      padding_left=10
      padding_right=10
    )
    ${sketchybar} --bar "''${bar[@]}"

    defaults=(
      updates=when_shown
      padding_left=4
      padding_right=4
      icon.font="JetBrainsMono Nerd Font:Bold:12.0"
      icon.color=${colors.fg}
      icon.highlight_color=${colors.fg}
      icon.padding_left=7
      icon.padding_right=4
      # .AppleSystemUIFont is the system font (SF): the "SF Pro" family name no
      # longer resolves through CoreText and silently falls back to Helvetica.
      label.font=".AppleSystemUIFont:Medium:12.5"
      label.color=${colors.fg}
      label.padding_left=4
      label.padding_right=7
      background.drawing=on
      background.color=${capsule.color}
      background.height=${toString capsule.height}
      background.corner_radius=${toString capsule.corner_radius}
      background.border_width=${toString capsule.border_width}
      background.border_color=${capsule.border_color}
    )
    ${sketchybar} --default "''${defaults[@]}"

    ${lib.concatMapStringsSep "\n" (event: "${sketchybar} --add event ${event}") cfg.sketchybar.events}

    ${lib.concatMapStringsSep "\n" renderItem allItems}

    ${lib.concatMapStringsSep "\n" renderBracket cfg.sketchybar.brackets}

    ${sketchybar} --update
    ${lib.concatMapStringsSep "\n" (event: "${sketchybar} --trigger ${event}") cfg.sketchybar.events}
  '';

in
{
  config = lib.mkIf (cfg.renderer == "sketchybar") {
    home.packages = [ pkgs.sketchybar ];

    # The LaunchAgent runs the immutable generated config directly. Its plist
    # therefore changes with the config, so Home Manager bootouts and
    # bootstraps the bar exactly once; a separate file onChange would race it
    # and cause the clear/refill/clear/refill sequence seen during switches.
    xdg.configFile."sketchybar/sketchybarrc".source = sketchybarConfig;

    launchd.agents.sketchybar = style.mkAgent "sketchybar" [
      sketchybar
      "--config"
      "${sketchybarConfig}"
    ];
  };
}
