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

  # Gruvbox palette (0xAARRGGBB)
  colors = {
    bar = "0xe6282828"; # bg0, mostly opaque
    fg = "0xffebdbb2"; # fg0
    fgInverse = "0xff282828"; # bg0, icon text on a highlighted item
    item = "0xff3c3836"; # bg1, default item background
    itemAlt = "0xff504945"; # bg2
    occupied = "0xff665c54"; # bg3, occupied but inactive workspace
    gray = "0xffa89984";
    red = "0xffcc241d";
    brightRed = "0xfffb4934";
    yellow = "0xffd79921";
    olive = "0xff98971a";
    green = "0xffb8bb26";
    teal = "0xff689d6a";
    aqua = "0xff83a598";
    blue = "0xff458588";
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

  clockPlugin = mkPlugin "clock" ''
    ${sketchybar} --set "$NAME" label="$(/bin/date '+%a %b %d  %H:%M:%S')"
  '';

  volumePlugin = mkPlugin "volume" ''
    if [ "$SENDER" = "mouse.clicked" ]; then
      /usr/bin/osascript -e 'set volume output muted not (output muted of (get volume settings))'
    fi

    volume="$(/usr/bin/osascript -e 'output volume of (get volume settings)')"
    muted="$(/usr/bin/osascript -e 'output muted of (get volume settings)')"

    if [ "$muted" = "true" ] || [ "$volume" -eq 0 ]; then
      icon="󰖁"
      color=${colors.red}
    elif [ "$volume" -lt 35 ]; then
      icon="󰕿"
      color=${colors.aqua}
    elif [ "$volume" -lt 70 ]; then
      icon="󰖀"
      color=${colors.aqua}
    else
      icon="󰕾"
      color=${colors.aqua}
    fi

    ${sketchybar} --set "$NAME" icon="$icon" icon.color="$color" label="$volume%"
  '';

  cpuPlugin = mkPlugin "cpu" ''
    cores="$(/usr/sbin/sysctl -n hw.logicalcpu)"
    cpu="$(/bin/ps -A -o %cpu= | /usr/bin/awk -v cores="$cores" '{ total += $1 } END { printf "%.0f", total / cores }')"
    ${sketchybar} --set "$NAME" label="$cpu%"
  '';

  memoryPlugin = mkPlugin "memory" ''
    total="$(/usr/sbin/sysctl -n hw.memsize)"
    page_size="$(/usr/sbin/sysctl -n hw.pagesize)"
    free_pages="$(/usr/bin/vm_stat | /usr/bin/awk '/Pages free/ { gsub("\\.", "", $3); print $3 }')"
    inactive_pages="$(/usr/bin/vm_stat | /usr/bin/awk '/Pages inactive/ { gsub("\\.", "", $3); print $3 }')"
    available=$(( (free_pages + inactive_pages) * page_size ))
    used=$(( total - available ))
    used_gib="$(/usr/bin/awk -v bytes="$used" 'BEGIN { printf "%.1f", bytes / 1073741824 }')"
    total_gib="$(/usr/bin/awk -v bytes="$total" 'BEGIN { printf "%.0f", bytes / 1073741824 }')"
    ${sketchybar} --set "$NAME" label="''${used_gib}G/''${total_gib}G"
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
      color=${colors.brightRed}
    elif [ "$percentage" -le 30 ]; then
      icon="󰁻"
      color=${colors.yellow}
    elif [ "$percentage" -le 60 ]; then
      icon="󰁾"
      color=${colors.olive}
    else
      icon="󰁹"
      color=${colors.olive}
    fi

    ${sketchybar} --set "$NAME" drawing=on icon="$icon" icon.color="$color" label="$percentage%"
  '';

  # ---------------------------------------------------------------------------
  # Bar items, declared as data and rendered below.
  # ---------------------------------------------------------------------------

  baseItems = [
    {
      name = "clock";
      side = "right";
      settings = {
        icon = "󰥔";
        "background.color" = colors.itemAlt;
        update_freq = 1;
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
    {
      name = "volume";
      side = "right";
      settings.script = volumePlugin;
      subscribe = [
        "volume_change"
        "mouse.clicked"
      ];
    }
    {
      name = "cpu";
      side = "right";
      settings = {
        icon = "󰍛";
        "icon.color" = colors.yellow;
        update_freq = 5;
        script = cpuPlugin;
      };
    }
    {
      name = "memory";
      side = "right";
      settings = {
        icon = "󰘚";
        "icon.color" = colors.blue;
        update_freq = 5;
        script = memoryPlugin;
      };
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

  sketchybarConfig = pkgs.writeShellScript "sketchybarrc" ''
    bar=(
      position=${barPosition}
      height=34
      color=${colors.bar}
      blur_radius=20
      margin=0
      y_offset=0
      corner_radius=0
      border_width=0
      shadow=off
      sticky=on
      topmost=window
      padding_left=6
      padding_right=6
    )
    ${sketchybar} --bar "''${bar[@]}"

    defaults=(
      updates=when_shown
      padding_left=3
      padding_right=3
      icon.font="JetBrainsMono Nerd Font:Bold:12.0"
      icon.color=${colors.fg}
      icon.highlight_color=${colors.fgInverse}
      icon.padding_left=7
      icon.padding_right=4
      label.font="JetBrainsMono Nerd Font:Medium:12.0"
      label.color=${colors.fg}
      label.padding_left=4
      label.padding_right=7
      background.drawing=on
      background.color=${colors.item}
      background.height=26
      background.corner_radius=10
    )
    ${sketchybar} --default "''${defaults[@]}"

    ${lib.concatMapStringsSep "\n" (event: "${sketchybar} --add event ${event}") cfg.sketchybar.events}

    ${lib.concatMapStringsSep "\n" renderItem allItems}

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
  options.dotfiles.panel.sketchybar.items = lib.mkOption {
    type = lib.types.listOf itemType;
    default = [ ];
    description = ''
      Extra bar items rendered after the built-in ones, letting feature
      modules contribute items without touching the sketchybar renderer.
    '';
  };

  options.dotfiles.panel.sketchybar.events = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Custom sketchybar events to register before items are added. Each
      event is triggered once at the end of the config so subscribers
      render their initial state.
    '';
  };

  config = lib.mkIf (cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    home.packages = [ pkgs.sketchybar ];

    xdg.configFile."sketchybar/sketchybarrc".source = sketchybarConfig;

    # Restart the bar whenever its config changes. `sketchybar --reload` only
    # re-runs the config path resolved when the process started, so after a
    # switch it keeps replaying the *previous* generation's sketchybarrc (and
    # drops any items the new config added). Kickstarting the launchd agent
    # re-execs sketchybar against the freshly linked config. Guard on the
    # process so a config change on fresh install doesn't fail the switch.
    xdg.configFile."sketchybar/sketchybarrc".onChange = ''
      if /usr/bin/pgrep -x sketchybar >/dev/null 2>&1; then
        echo "SketchyBar config changed, restarting..."
        /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/org.nix-community.home.sketchybar"
      else
        echo "SketchyBar not running; new config will be loaded on next launch"
      fi
    '';

    launchd.agents.sketchybar = mkAgent "sketchybar" [
      sketchybar
      "--config"
      "${config.xdg.configHome}/sketchybar/sketchybarrc"
    ];
  };
}
