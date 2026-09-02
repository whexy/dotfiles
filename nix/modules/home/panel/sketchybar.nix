# SketchyBar status bar configuration (macOS)
#
# This file owns the bar itself: appearance, the item renderer, and the
# built-in right-side pills. Feature modules contribute items through
# `dotfiles.panel.sketchybar.items` and custom events through
# `dotfiles.panel.sketchybar.events` (see ./wm and ./ai-quota).
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;
  osConfig = args.osConfig or null;

  autoHideMenuBar = osConfig != null && (osConfig.dotfiles.hardware.display.autoHideMenuBar or true);
  barPosition = if autoHideMenuBar then "top" else "bottom";

  sketchybar = lib.getExe pkgs.sketchybar;

  # macOS Liquid Glass palette (0xAARRGGBB): dark-variant system colors for
  # state, translucent white tints for the glass capsules. Status icons stay
  # monochrome white; color is reserved for state (charging, low, muted) and
  # the accent-blue active workspace.
  colors = {
    bar = "0x00000000"; # fully transparent, wallpaper shows through
    fg = "0xffffffff"; # primary text/icons
    glass = "0x1affffff"; # 10% white, default item capsule
    glassBorder = "0x40ffffff"; # 25% white hairline, capsule edge highlight
    red = "0xffff453a"; # systemRed: muted, critical
    yellow = "0xffffd60a"; # systemYellow: battery low, quota warning
    green = "0xff30d158"; # systemGreen: charging
  };

  mkPlugin = name: pkgs.writeShellScript "sketchybar-${name}";

  # Extension point so other feature modules (e.g. the ai-quota pills) can
  # contribute bar items without touching this file's rendering logic.
  itemType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      kind = lib.mkOption {
        type = lib.types.enum [
          "item"
          "slider"
        ];
        default = "item";
      };
      width = lib.mkOption {
        type = lib.types.ints.positive;
        default = 40;
      };
      side = lib.mkOption {
        # "left", "right", or "popup.<item>" to nest inside an item's popup.
        type = lib.types.strMatching "left|right|popup\\..+";
      };
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      clickScript = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      subscribe = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  # A bracket draws one shared background behind a set of member items (the
  # `stats` capsule is a hardcoded example below). Feature modules use this to
  # group their own items, e.g. the wm module's workspace capsule.
  bracketType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      members = lib.mkOption { type = lib.types.listOf lib.types.str; };
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
    };
  };

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
      position=${barPosition}
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
      background.color=${colors.glass}
      background.height=26
      background.corner_radius=13
      background.border_width=1
      background.border_color=${colors.glassBorder}
    )
    ${sketchybar} --default "''${defaults[@]}"

    ${lib.concatMapStringsSep "\n" (event: "${sketchybar} --add event ${event}") cfg.sketchybar.events}

    ${lib.concatMapStringsSep "\n" renderItem allItems}

    ${lib.concatMapStringsSep "\n" renderBracket cfg.sketchybar.brackets}

    ${sketchybar} --update
    ${lib.concatMapStringsSep "\n" (event: "${sketchybar} --trigger ${event}") cfg.sketchybar.events}
  '';

  mkAgent = name: programArguments: {
    enable = true;
    config = {
      ProgramArguments = programArguments;
      ProcessType = "Interactive";
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${name}.err.log";
    };
  };
in
{
  options.dotfiles.panel.sketchybar = {
    items = lib.mkOption {
      type = lib.types.listOf itemType;
      default = [ ];
      description = ''
        Extra bar items rendered after the built-in ones, letting feature
        modules contribute items without touching the sketchybar renderer.
      '';
    };

    events = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Custom sketchybar events to register before items are added. Each
        event is triggered once at the end of the config so subscribers
        render their initial state.
      '';
    };

    brackets = lib.mkOption {
      type = lib.types.listOf bracketType;
      default = [ ];
      description = ''
        Brackets rendered after all items, letting feature modules draw one
        shared background behind a group of items they contributed.
      '';
    };
  };

  config = lib.mkIf (cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    home.packages = [ pkgs.sketchybar ];

    # The LaunchAgent runs the immutable generated config directly. Its plist
    # therefore changes with the config, so Home Manager bootouts and
    # bootstraps the bar exactly once; a separate file onChange would race it
    # and cause the clear/refill/clear/refill sequence seen during switches.
    xdg.configFile."sketchybar/sketchybarrc".source = sketchybarConfig;

    launchd.agents.sketchybar = mkAgent "sketchybar" [
      sketchybar
      "--config"
      "${sketchybarConfig}"
    ];
  };
}
