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
  showWorkspaces = windowManager == "aerospace";

  workspacePlugin = pkgs.writeShellScript "sketchybar-workspace" ''
    focused="''${FOCUSED_WORKSPACE:-$(${aerospace} list-workspaces --focused 2>/dev/null | /usr/bin/head -n 1)}"

    workspace="''${NAME#space.}"
    if [ "$workspace" = "$focused" ]; then
      ${sketchybar} --set "$NAME" \
        icon.highlight=on \
        background.color=0xff458588
    else
      ${sketchybar} --set "$NAME" \
        icon.highlight=off \
        background.color=0xff3c3836
    fi
  '';

  frontAppPlugin = pkgs.writeShellScript "sketchybar-front-app" ''
    if [ "$SENDER" = "front_app_switched" ] && [ -n "''${INFO:-}" ]; then
      app="$INFO"
    else
      ${
        if windowManager == "paneru" then
          ''app="$(${paneru} query active --json 2>/dev/null | ${jq} -r '.focused_app_name // empty')"''
        else
          ''app="$(${aerospace} list-windows --focused --format '%{app-name}' 2>/dev/null | /usr/bin/head -n 1)"''
      }
    fi

    ${sketchybar} --set "$NAME" label="''${app:-Desktop}"
  '';

  clockPlugin = pkgs.writeShellScript "sketchybar-clock" ''
    ${sketchybar} --set "$NAME" label="$(/bin/date '+%a %b %d  %H:%M:%S')"
  '';

  volumePlugin = pkgs.writeShellScript "sketchybar-volume" ''
    if [ "$SENDER" = "mouse.clicked" ]; then
      /usr/bin/osascript -e 'set volume output muted not (output muted of (get volume settings))'
    fi

    volume="$(/usr/bin/osascript -e 'output volume of (get volume settings)')"
    muted="$(/usr/bin/osascript -e 'output muted of (get volume settings)')"

    if [ "$muted" = "true" ] || [ "$volume" -eq 0 ]; then
      icon="󰖁"
      color="0xffcc241d"
    elif [ "$volume" -lt 35 ]; then
      icon="󰕿"
      color="0xff83a598"
    elif [ "$volume" -lt 70 ]; then
      icon="󰖀"
      color="0xff83a598"
    else
      icon="󰕾"
      color="0xff83a598"
    fi

    ${sketchybar} --set "$NAME" icon="$icon" icon.color="$color" label="$volume%"
  '';

  networkPlugin = pkgs.writeShellScript "sketchybar-network" ''
    interface="$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/ { print $2; exit }')"

    if [ -z "$interface" ]; then
      ${sketchybar} --set "$NAME" icon="󰤭" icon.color=0xffcc241d label="offline"
      exit 0
    fi

    network="$(/usr/sbin/networksetup -getairportnetwork "$interface" 2>/dev/null || true)"
    case "$network" in
      "Current Wi-Fi Network: "*)
        ssid="''${network#Current Wi-Fi Network: }"
        ${sketchybar} --set "$NAME" icon="󰤨" icon.color=0xff689d6a label="$ssid"
        ;;
      *)
        ${sketchybar} --set "$NAME" icon="󰈀" icon.color=0xff689d6a label="$interface"
        ;;
    esac
  '';

  cpuPlugin = pkgs.writeShellScript "sketchybar-cpu" ''
    cores="$(/usr/sbin/sysctl -n hw.logicalcpu)"
    cpu="$(/bin/ps -A -o %cpu= | /usr/bin/awk -v cores="$cores" '{ total += $1 } END { printf "%.0f", total / cores }')"
    ${sketchybar} --set "$NAME" label="$cpu%"
  '';

  memoryPlugin = pkgs.writeShellScript "sketchybar-memory" ''
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

  batteryPlugin = pkgs.writeShellScript "sketchybar-battery" ''
    battery="$(/usr/bin/pmset -g batt)"
    percentage="$(printf '%s\n' "$battery" | /usr/bin/grep -Eo '[0-9]+%' | /usr/bin/head -n 1 | /usr/bin/tr -d '%')"

    if [ -z "$percentage" ]; then
      ${sketchybar} --set "$NAME" drawing=off
      exit 0
    fi

    if printf '%s\n' "$battery" | /usr/bin/grep -q 'AC Power'; then
      icon="󰂄"
      color="0xffb8bb26"
    elif [ "$percentage" -le 15 ]; then
      icon="󰂃"
      color="0xfffb4934"
    elif [ "$percentage" -le 30 ]; then
      icon="󰁻"
      color="0xffd79921"
    elif [ "$percentage" -le 60 ]; then
      icon="󰁾"
      color="0xff98971a"
    else
      icon="󰁹"
      color="0xff98971a"
    fi

    ${sketchybar} --set "$NAME" drawing=on icon="$icon" icon.color="$color" label="$percentage%"
  '';

  paneruEventBridge = pkgs.writeShellScript "sketchybar-paneru-events" ''
    while true; do
      ${paneru} subscribe --json 2>/dev/null | while IFS= read -r _event; do
        ${sketchybar} --trigger wm_state_change
      done
      /bin/sleep 1
    done
  '';

  sketchybarConfig = pkgs.writeShellScript "sketchybarrc" ''
    bar=(
      position=${barPosition}
      height=34
      color=0xe6282828
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
      icon.color=0xffebdbb2
      icon.highlight_color=0xff282828
      icon.padding_left=7
      icon.padding_right=4
      label.font="JetBrainsMono Nerd Font:Medium:12.0"
      label.color=0xffebdbb2
      label.padding_left=4
      label.padding_right=7
      background.drawing=on
      background.color=0xff3c3836
      background.height=26
      background.corner_radius=10
    )
    ${sketchybar} --default "''${defaults[@]}"

    ${sketchybar} --add event wm_state_change

    ${lib.optionalString showWorkspaces ''
      for workspace in {1..9}; do
        ${sketchybar} --add item "space.$workspace" left \
          --set "space.$workspace" \
            icon="$workspace" \
            label.drawing=off \
            icon.padding_left=8 \
            icon.padding_right=8 \
            script="${workspacePlugin}" \
            click_script="${aerospace} workspace $workspace" \
          --subscribe "space.$workspace" wm_state_change
      done
    ''}

    ${sketchybar} --add item front_app left \
      --set front_app \
        icon="󰣆" \
        icon.color=0xffa89984 \
        label.color=0xffa89984 \
        label.max_chars=40 \
        script="${frontAppPlugin}" \
      --subscribe front_app front_app_switched wm_state_change

    ${sketchybar} --add item clock right \
      --set clock \
        icon="󰥔" \
        background.color=0xff504945 \
        update_freq=1 \
        script="${clockPlugin}" \
        click_script="/usr/bin/open -a Calendar"

    ${sketchybar} --add item battery right \
      --set battery \
        update_freq=60 \
        script="${batteryPlugin}" \
        click_script="/usr/bin/open x-apple.systempreferences:com.apple.Battery-Settings.extension" \
      --subscribe battery system_woke power_source_change

    ${sketchybar} --add item volume right \
      --set volume script="${volumePlugin}" \
      --subscribe volume volume_change mouse.clicked

    ${sketchybar} --add item network right \
      --set network \
        update_freq=15 \
        script="${networkPlugin}" \
        click_script="/usr/bin/open x-apple.systempreferences:com.apple.Network-Settings.extension" \
      --subscribe network system_woke

    ${sketchybar} --add item cpu right \
      --set cpu \
        icon="󰍛" \
        icon.color=0xffd79921 \
        update_freq=5 \
        script="${cpuPlugin}"

    ${sketchybar} --add item memory right \
      --set memory \
        icon="󰘚" \
        icon.color=0xff458588 \
        update_freq=5 \
        script="${memoryPlugin}"

    ${sketchybar} --update
    ${sketchybar} --trigger wm_state_change
  '';
in
{
  config = lib.mkIf (cfg.sketchybar.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    home.packages = [ pkgs.sketchybar ];

    xdg.configFile."sketchybar/sketchybarrc".source = sketchybarConfig;

    launchd.agents.sketchybar = {
      enable = true;
      config = {
        ProgramArguments = [
          sketchybar
          "--config"
          "${config.xdg.configHome}/sketchybar/sketchybarrc"
        ];
        ProcessType = "Interactive";
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sketchybar.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sketchybar.err.log";
      };
    };

    launchd.agents.sketchybar-paneru-events = lib.mkIf (wmEnabled && windowManager == "paneru") {
      enable = true;
      config = {
        ProgramArguments = [ "${paneruEventBridge}" ];
        ProcessType = "Interactive";
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sketchybar-paneru.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sketchybar-paneru.err.log";
      };
    };
  };
}
