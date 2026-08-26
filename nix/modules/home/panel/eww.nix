# Eww status bar configuration (Linux).
#
# Renderer counterpart of ./waybar.nix, selected by
# dotfiles.panel.linuxBar. Feature modules contribute through the
# extension points below instead of editing the window definition:
# defs appends yuck definitions (defpoll/defvar/defwidget), styles
# appends SCSS (palette variables stay in scope), and left/center/right
# name the widgets placed in the bar's three slots.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.panel;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  enabled = cfg.waybar.enable && cfg.linuxBar == "eww" && (!isDarwin);

  eww = lib.getExe pkgs.eww;
  ip = lib.getExe' pkgs.iproute2 "ip";
  iwgetid = lib.getExe' pkgs.wirelesstools "iwgetid";
  bluetoothctl = lib.getExe' pkgs.bluez "bluetoothctl";
  blueman-manager = lib.getExe' pkgs.blueman "blueman-manager";
  sleep = lib.getExe' pkgs.coreutils "sleep";
  gawk = lib.getExe pkgs.gawk;
  statusNotifierWatcher = pkgs.haskell.lib.justStaticExecutables pkgs.haskellPackages.status-notifier-item;

  batteryScript = pkgs.writeShellScript "eww-battery" ''
    dir="$(printf '%s\n' /sys/class/power_supply/BAT* | head -n1)"
    [ -d "$dir" ] || exit 0

    capacity="$(cat "$dir/capacity")"
    case "$(cat "$dir/status")" in
      Charging|Full) icon=󰂄 ;;
      *) icon=󰁹 ;;
    esac
    echo "$icon $capacity%"
  '';

  networkScript = pkgs.writeShellScript "eww-network" ''
    route="$(${ip} route show default 2>/dev/null | head -n1)"
    if [ -z "$route" ]; then
      echo "󰤭 disconnected"
      exit 0
    fi

    iface="$(printf '%s\n' "$route" | ${gawk} '{for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1)}')"
    if ${gawk} -v iface="$iface" '$1 ~ iface":" { found = 1 } END { exit !found }' /proc/net/wireless 2>/dev/null; then
      ssid="$(${iwgetid} "$iface" --raw 2>/dev/null)"
      echo "󰤨 ''${ssid:-wifi}"
    else
      addr="$(${ip} -4 addr show "$iface" 2>/dev/null | ${gawk} '/inet /{split($2, a, "/"); print a[1]}')"
      echo "󰈀 $addr"
    fi
  '';

  bluetoothScript = pkgs.writeShellScript "eww-bluetooth" ''
    ${bluetoothctl} show 2>/dev/null | grep -q "Powered: yes" || exit 0

    count="$(${bluetoothctl} devices Connected 2>/dev/null | wc -l)"
    if [ "$count" -gt 0 ]; then
      echo "󰂱 $count"
    else
      echo "󰂯"
    fi
  '';

  startScript = pkgs.writeShellScript "eww-bar-open" ''
    # The daemon unit starts concurrently; wait for its socket before opening.
    socket="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/eww/eww.sock"
    for _ in {1..40}; do
      [ -S "$socket" ] && break
      ${sleep} 0.25
    done

    # This unit's X-Restart-Triggers pin the generated config store paths, so
    # HM's sd-switch reruns it whenever the config changes; eww does not watch
    # its files on its own.
    ${eww} reload 2>/dev/null || true
    exec ${eww} open bar
  '';

  renderWidgets = names: lib.concatStringsSep " " (map (n: "(${n})") names);

  yuck = ''
    ${cfg.eww.defs}

    ; --- Core widgets ---
    (defpoll CLOCK :interval "1s" "date +%H:%M:%S")
    (defpoll BATTERY :interval "30s" "${batteryScript}")
    (defpoll NETWORK :interval "5s" "${networkScript}")
    (defpoll BLUETOOTH :interval "5s" "${bluetoothScript}")

    (defwidget core-tray []
      (box :class "pill tray"
        (systray :orientation "horizontal" :icon-size 14 :spacing 8 :prepend-new false)))
    (defwidget core-battery []
      (box :class "pill battery" :visible {BATTERY != ""} (label :text BATTERY)))
    (defwidget core-network [] (box :class "pill network" (label :text NETWORK)))
    (defwidget core-cpu []
      (box :class "pill cpu" :tooltip {"Average frequency: " + round(jq(EWW_CPU.cores, "map(.freq) | add / length") / 1000, 2) + " GHz"}
        (label :text {"󰍛 " + round(EWW_CPU.avg, 0) + "%"})))
    (defwidget core-memory []
      (box :class "pill memory" :tooltip {round(EWW_RAM.used_mem_perc, 1) + "% used"}
        (label :text {"󰘚 " + formatbytes(EWW_RAM.total_mem - EWW_RAM.available_mem, true, "iec") + "/" + formatbytes(EWW_RAM.total_mem, true, "iec")})))
    (defwidget core-disk []
      (box :class "pill disk" :tooltip {formatbytes(EWW_DISK["/"].used, false, "iec") + " used / " + formatbytes(EWW_DISK["/"].total, false, "iec") + " total"}
        (label :text {"󰋊 " + formatbytes(EWW_DISK["/"].free, true, "iec")})))
    (defwidget core-bluetooth []
      (eventbox :onclick "${blueman-manager} &" :visible {BLUETOOTH != ""}
        (box :class "pill bluetooth" (label :text BLUETOOTH))))
    (defwidget clock [] (box :class "pill clock" (label :text CLOCK)))

    (defwidget bar-layout []
      (centerbox :orientation "h" :hexpand true
        (box :orientation "h" :halign "start" :space-evenly false ${renderWidgets cfg.eww.left})
        (box :orientation "h" :halign "center" :space-evenly false ${renderWidgets cfg.eww.center})
        (box :orientation "h" :halign "end" :space-evenly false ${renderWidgets cfg.eww.right})))

    (defwindow bar
      :monitor 0
      :geometry (geometry :x "0%" :y "0%" :width "100%" :height "30px" :anchor "bottom center")
      :stacking "fg"
      :exclusive true
      (bar-layout))
  '';

  # Material You (Material 3) dark palette: tone-80 accent text over dark
  # surface containers. Feature modules append state rules through
  # dotfiles.panel.eww.styles and can reuse these variables (same file).
  scss = ''
    // Material You dark palette.
    $primary: #d0bcff;
    $on-primary: #381e72;
    $primary-container: #4f378b;
    $on-primary-container: #eaddff;
    $secondary-container: #4a4458;
    $error: #f2b8b5;
    $warning: #eac46d;
    $surface: #141218;
    $surface-container-high: #2b2930;
    $surface-container-highest: #36343b;
    $on-surface: #e6e0e9;
    $on-surface-variant: #cac4d0;
    $on-surface-dim: rgba(230, 224, 233, 0.5);

    * {
      all: unset;
      font-family: "JetBrainsMono Nerd Font", monospace;
      font-size: 12px;
    }

    #bar {
      background-color: rgba(20, 18, 24, 0.92);
      color: $on-surface;
      padding: 0 4px;
    }

    // Tonal chips: full-rounded containers with tone-80 accent text.
    .pill {
      background-color: $surface-container-high;
      border-radius: 13px;
      padding: 2px 12px;
      margin: 4px 3px;
    }

    .tray {
      padding-left: 8px;
      padding-right: 8px;
    }

    .network {
      color: #a8c7fa;
    }

    .cpu {
      color: #efb8c8;
    }

    .memory {
      color: #ccc2dc;
    }

    .disk {
      color: #d0bcff;
    }

    .bluetooth {
      color: #80d5c6;
    }

    .bluetooth:hover {
      background-color: $surface-container-highest;
    }

    .battery {
      color: #b1d18b;
    }

    // Filled tonal button: the bar's one saturated element.
    .clock {
      background-color: $primary-container;
      color: $on-primary-container;
      font-weight: bold;
    }

    ${cfg.eww.styles}
  '';

  # Store-path copies double as reload triggers for the opener unit below;
  # feeding them through readFile keeps the deployed text identical.
  yuckFile = pkgs.writeText "eww.yuck" yuck;
  scssFile = pkgs.writeText "eww.scss" scss;
in
{
  options.dotfiles.panel.eww = {
    defs = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra yuck definitions (defpoll/defvar/defwidget) merged into eww.yuck.";
    };

    styles = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra SCSS appended to eww.scss after the base styles, so the Material You palette variables stay in scope.";
    };

    left = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Widget names shown on the bar's left slot.";
    };

    center = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Widget names shown on the bar's center slot.";
    };

    right = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Widget names shown on the bar's right slot.";
    };
  };

  config = lib.mkIf enabled {
    programs.eww = {
      enable = true;
      yuckConfig = builtins.readFile yuckFile;
      scssConfig = builtins.readFile scssFile;
      systemd.enable = true;
    };

    # Start the watcher independently so tray clients can register before the
    # visible host exists and keep their registration across Eww reloads.
    services.status-notifier-watcher = {
      enable = true;
      package = statusNotifierWatcher;
    };

    dotfiles.panel.eww = {
      left = lib.mkDefault [ ];
      center = lib.mkDefault [ "clock" ];
      # Core widgets must remain when feature modules append their pills.
      right = lib.mkBefore [
        "core-tray"
        "core-battery"
        "core-bluetooth"
        "core-network"
        "core-cpu"
        "core-memory"
        "core-disk"
      ];
    };

    systemd.user.services = {
      status-notifier-watcher = {
        Unit = {
          Before = [
            "tray.target"
            "eww.service"
          ];
          PartOf = [ "graphical-session.target" ];
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      eww.Unit = {
        Requires = [ "status-notifier-watcher.service" ];
        After = [ "status-notifier-watcher.service" ];
      };
    };

    # The HM eww module only starts the daemon; this opens the bar window
    # once the daemon socket is up, and reruns on every config change to
    # reload it (see startScript).
    systemd.user.services.eww-bar = {
      Unit = {
        Description = "Eww status bar window";
        BindsTo = [ "eww.service" ];
        After = [ "eww.service" ];
        X-Restart-Triggers = [
          yuckFile
          scssFile
        ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = startScript;
        RemainAfterExit = true;
      };
      Install.WantedBy = [ "eww.service" ];
    };
  };
}
