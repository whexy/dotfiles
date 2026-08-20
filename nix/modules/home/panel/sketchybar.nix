# SketchyBar status bar configuration (macOS)
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
  aerospace = lib.getExe pkgs.unstable.aerospace;
  paneru = lib.getExe config.services.paneru.finalPackage;
  jq = lib.getExe pkgs.jq;

  wmEnabled = config.dotfiles.wm.darwin.enable;
  windowManager = config.dotfiles.wm.darwin.windowManager;
  isPaneru = windowManager == "paneru";

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

  # Workspace items highlight the active workspace. On Paneru, occupied
  # virtual workspaces get a dimmed background and empty slots stay muted
  # (Paneru reports stable numbered slots).
  workspacePlugin = mkPlugin "workspace" ''
    set_state() {
      ${sketchybar} --set "$NAME" icon.highlight="$1" background.color="$2"
    }

    workspace="''${NAME#space.}"
    ${
      if isPaneru then
        ''
          state="$(${paneru} query virtual-workspaces --json 2>/dev/null | ${jq} -r --argjson n "$workspace" '.[] | select(.number == $n) | "\(.active) \(.windows | length)"' 2>/dev/null)"
          active="''${state%% *}"
          count="''${state#* }"

          if [ "$active" = "true" ]; then
            set_state on ${colors.blue}
          elif [ "''${count:-0}" -gt 0 ] 2>/dev/null; then
            set_state off ${colors.occupied}
          else
            set_state off ${colors.item}
          fi
        ''
      else
        ''
          focused="''${FOCUSED_WORKSPACE:-$(${aerospace} list-workspaces --focused 2>/dev/null | /usr/bin/head -n 1)}"

          if [ "$workspace" = "$focused" ]; then
            set_state on ${colors.blue}
          else
            set_state off ${colors.item}
          fi
        ''
    }
  '';

  frontAppPlugin = mkPlugin "front-app" ''
    if [ "$SENDER" = "front_app_switched" ] && [ -n "''${INFO:-}" ]; then
      app="$INFO"
    else
      ${
        if isPaneru then
          ''app="$(${paneru} query active --json 2>/dev/null | ${jq} -r '.focused_app_name // empty')"''
        else
          ''app="$(${aerospace} list-windows --focused --format '%{app-name}' 2>/dev/null | /usr/bin/head -n 1)"''
      }
    fi

    ${sketchybar} --set "$NAME" label="''${app:-Desktop}"
  '';

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

  networkPlugin = mkPlugin "network" ''
    interface="$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/ { print $2; exit }')"

    if [ -z "$interface" ]; then
      ${sketchybar} --set "$NAME" icon="󰤭" icon.color=${colors.red} label="offline"
      exit 0
    fi

    network="$(/usr/sbin/networksetup -getairportnetwork "$interface" 2>/dev/null || true)"
    case "$network" in
      "Current Wi-Fi Network: "*)
        ssid="''${network#Current Wi-Fi Network: }"
        ${sketchybar} --set "$NAME" icon="󰤨" icon.color=${colors.teal} label="$ssid"
        ;;
      *)
        ${sketchybar} --set "$NAME" icon="󰈀" icon.color=${colors.teal} label="$interface"
        ;;
    esac
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

  # Bridges `paneru subscribe` events into the sketchybar `wm_state_change`
  # event that workspace and front-app items subscribe to.
  paneruEventBridge = mkPlugin "paneru-events" ''
    while true; do
      ${paneru} subscribe --json 2>/dev/null | while IFS= read -r _event; do
        ${sketchybar} --trigger wm_state_change
      done
      /bin/sleep 1
    done
  '';

  # ---------------------------------------------------------------------------
  # Bar items, declared as data and rendered below.
  # ---------------------------------------------------------------------------

  workspaceItem = n: {
    name = "space.${toString n}";
    side = "left";
    settings = {
      icon = n;
      "label.drawing" = "off";
      "icon.padding_left" = 8;
      "icon.padding_right" = 8;
      script = workspacePlugin;
    };
    clickScript =
      if isPaneru then
        "${paneru} send-cmd window virtualnum ${toString n}"
      else
        "${aerospace} workspace ${toString n}";
    subscribe = [ "wm_state_change" ];
  };

  items = (map workspaceItem (lib.range 1 9)) ++ [
    {
      name = "front_app";
      side = "left";
      settings = {
        icon = "󰣆";
        "icon.color" = colors.gray;
        "label.color" = colors.gray;
        "label.max_chars" = 40;
        script = frontAppPlugin;
      };
      subscribe = [
        "front_app_switched"
        "wm_state_change"
      ];
    }
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
      name = "network";
      side = "right";
      settings = {
        update_freq = 15;
        script = networkPlugin;
      };
      clickScript = "/usr/bin/open x-apple.systempreferences:com.apple.Network-Settings.extension";
      subscribe = [ "system_woke" ];
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

  renderItem =
    item:
    let
      settings = lib.concatStringsSep " " (
        lib.mapAttrsToList (k: v: ''${k}="${toString v}"'') item.settings
      );
      click = lib.optionalString (item ? clickScript) " click_script=\"${item.clickScript}\"";
      events = lib.optionalString (
        item ? subscribe
      ) " --subscribe ${item.name} ${lib.concatStringsSep " " item.subscribe}";
    in
    ''
      ${sketchybar} --add item ${item.name} ${item.side} \
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

    ${sketchybar} --add event wm_state_change

    ${lib.concatMapStringsSep "\n" renderItem items}

    ${sketchybar} --update
    ${sketchybar} --trigger wm_state_change
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
  config = lib.mkIf (cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    home.packages = [ pkgs.sketchybar ];

    xdg.configFile."sketchybar/sketchybarrc".source = sketchybarConfig;

    launchd.agents.sketchybar = mkAgent "sketchybar" [
      sketchybar
      "--config"
      "${config.xdg.configHome}/sketchybar/sketchybarrc"
    ];

    launchd.agents.sketchybar-paneru-events = lib.mkIf (wmEnabled && isPaneru) (
      mkAgent "sketchybar-paneru" [ "${paneruEventBridge}" ]
    );
  };
}
