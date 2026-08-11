# Waybar status bar configuration (Linux)
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
in
{
  config = lib.mkIf cfg.waybar.enable (
    lib.mkIf (!isDarwin) {
      programs.waybar = {
        enable = true;
        systemd.enable = true;

        settings = {
          mainBar = {
            layer = "top";
            position = "bottom";
            height = 30;
            spacing = 4;

            modules-left = [
              "niri/workspaces"
              "idle_inhibitor"
              "niri/window"
            ];
            modules-center = [
              "clock"
            ];
            modules-right = [
              "tray"
              "battery"
              "bluetooth"
              "network"
              "cpu"
              "memory"
              "disk"
            ];

            "niri/workspaces" = {
              format = "{index}";
            };

            "niri/window" = {
              format = "{}";
              max-length = 50;
              rewrite = {
                "(.*) — Mozilla Firefox" = "󰈹 $1";
                "(.*) - fish" = " $1";
                "(.*)" = "$1";
              };
            };

            idle_inhibitor = {
              format = "{icon}";
              format-icons = {
                activated = "󰅶";
                deactivated = "󰾪";
              };
              tooltip-format-activated = "Idle inhibitor: on";
              tooltip-format-deactivated = "Idle inhibitor: off";
            };

            tray = {
              icon-size = 14;
              spacing = 8;
            };

            bluetooth = {
              format = "󰂯";
              format-disabled = "";
              format-off = "󰂲";
              format-connected = "󰂱 {device_alias}";
              tooltip-format = "{controller_alias}\t{controller_address}";
              tooltip-format-connected = "{device_enumerate}";
              on-click = "${pkgs.blueman}/bin/blueman-manager";
            };

            battery = {
              format = "{icon} {capacity}%";
              format-charging = "󰂄 {capacity}%";
              format-plugged = "󰚥 {capacity}%";
              format-full = "󰁹 {capacity}%";
              format-icons = [
                "󰁺"
                "󰁻"
                "󰁼"
                "󰁽"
                "󰁾"
                "󰁿"
                "󰂀"
                "󰂁"
                "󰂂"
                "󰁹"
              ];
              states = {
                warning = 30;
                critical = 15;
              };
              interval = 30;
              tooltip-format = "{timeTo} ({power}W)";
            };

            network = {
              format-wifi = "󰤨 {essid} ({signalStrength}%)";
              format-ethernet = "󰈀 {ipaddr}";
              format-disconnected = "󰤭 disconnected";
              tooltip-format = "{ipaddr}/{cidr} via {gwaddr}";
              interval = 5;
            };

            cpu = {
              format = "󰍛 {usage}%";
              interval = 5;
              tooltip-format = "{avg_frequency} GHz";
            };

            memory = {
              format = "󰘚 {used:0.1f}G/{total:0.1f}G";
              interval = 5;
              tooltip-format = "{percentage}% used";
            };

            disk = {
              format = "󰋊 {free}";
              path = "/";
              interval = 30;
              tooltip-format = "{used} used / {total} total";
            };

            clock = {
              format = "{:%H:%M:%S}";
              format-alt = "{:%Y-%m-%d %A}";
              interval = 1;
              tooltip-format = "<tt><small>{calendar}</small></tt>";
              calendar = {
                mode = "year";
                mode-mon-col = 3;
                weeks-pos = "right";
                on-scroll = 1;
                format = {
                  months = "<span color='#d79921'><b>{}</b></span>";
                  days = "<span color='#ebdbb2'>{}</span>";
                  weekdays = "<span color='#458588'><b>{}</b></span>";
                  weeks = "<span color='#928374'>W{}</span>";
                  today = "<span color='#cc241d'><b><u>{}</u></b></span>";
                };
              };
            };
          };
        };

        # Gruvbox-inspired pill styling
        style = ''
          * {
            font-family: "JetBrainsMono Nerd Font", monospace;
            font-size: 12px;
            min-height: 0;
          }

          window#waybar {
            background-color: rgba(40, 40, 40, 0.9);
            color: #ebdbb2;
          }

          /* Pill-shaped module styling */
          #workspaces,
          #window,
          #idle_inhibitor,
          #tray,
          #battery,
          #bluetooth,
          #network,
          #cpu,
          #memory,
          #disk,
          #clock {
            padding: 2px 10px;
            margin: 3px 2px;
            border-radius: 10px;
            background-color: #3c3836;
            transition: all 0.3s ease;
          }

          /* Workspaces */
          #workspaces {
            padding: 0;
            background-color: transparent;
          }

          #workspaces button {
            padding: 2px 8px;
            margin: 3px 1px;
            border-radius: 10px;
            color: #928374;
            background-color: #3c3836;
            border: none;
            transition: all 0.3s ease;
          }

          #workspaces button:hover {
            background-color: #504945;
            color: #ebdbb2;
          }

          #workspaces button.active {
            color: #282828;
            background-color: #458588;
            font-weight: bold;
          }

          /* Window title */
          #window {
            color: #a89984;
            font-style: italic;
          }

          /* Idle inhibitor */
          #idle_inhibitor {
            color: #928374;
          }

          #idle_inhibitor.activated {
            color: #282828;
            background-color: #d79921;
          }

          /* Tray */
          #tray {
            background-color: #3c3836;
          }

          #tray > .passive {
            -gtk-icon-effect: dim;
          }

          #tray > .needs-attention {
            -gtk-icon-effect: highlight;
            background-color: #cc241d;
            border-radius: 10px;
          }

          /* Network */
          #network {
            color: #689d6a;
          }

          #network.disconnected {
            color: #cc241d;
            background-color: #3c3836;
          }

          #network:hover {
            background-color: #689d6a;
            color: #282828;
          }

          /* CPU */
          #cpu {
            color: #d79921;
          }

          #cpu:hover {
            background-color: #d79921;
            color: #282828;
          }

          /* Memory */
          #memory {
            color: #458588;
          }

          #memory:hover {
            background-color: #458588;
            color: #282828;
          }

          /* Disk */
          #disk {
            color: #b16286;
          }

          #disk:hover {
            background-color: #b16286;
            color: #282828;
          }

          /* Bluetooth */
          #bluetooth {
            color: #83a598;
          }

          #bluetooth:hover {
            background-color: #83a598;
            color: #282828;
          }

          /* Battery */
          #battery {
            color: #98971a;
          }

          #battery.charging,
          #battery.plugged {
            color: #b8bb26;
          }

          #battery.warning:not(.charging) {
            color: #d79921;
          }

          #battery.critical:not(.charging) {
            color: #fb4934;
            animation: blink 1s linear infinite alternate;
          }

          #battery:hover {
            background-color: #98971a;
            color: #282828;
          }

          /* Clock */
          #clock {
            color: #ebdbb2;
            font-weight: bold;
            background-color: #504945;
          }

          #clock:hover {
            background-color: #ebdbb2;
            color: #282828;
          }

          /* Blink animation for critical states */
          @keyframes blink {
            to {
              background-color: #fb4934;
            }
          }
        '';
      };
    }
  );
}
