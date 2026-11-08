# Waybar status bar configuration (Linux).
#
# One of the two renderers for the Linux bar, selected by
# dotfiles.panel.linuxBar. Feature modules (wm, ai-quota, renpho) merge
# their settings in with mkOrder, so this file stays feature-agnostic.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../desktop/style.nix) colors font;
in
{
  config = lib.mkIf (config.dotfiles.panel.renderer == "waybar") {
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
            "idle_inhibitor"
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
                months = "<span color='${colors.yellow}'><b>{}</b></span>";
                days = "<span color='${colors.fg}'>{}</span>";
                weekdays = "<span color='${colors.blue}'><b>{}</b></span>";
                weeks = "<span color='${colors.gray}'>W{}</span>";
                today = "<span color='${colors.red}'><b><u>{}</u></b></span>";
              };
            };
          };
        };
      };

      # Gruvbox pill styling (../desktop/style.nix)
      style = ''
        * {
          font-family: "${font}", monospace;
          font-size: 12px;
          min-height: 0;
        }

        window#waybar {
          background-color: rgba(40, 40, 40, 0.9);
          color: ${colors.fg};
        }

        /* Pill-shaped module styling */
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
          background-color: ${colors.bg1};
          transition: all 0.3s ease;
        }

        /* Idle inhibitor */
        #idle_inhibitor {
          color: ${colors.gray};
        }

        #idle_inhibitor.activated {
          color: ${colors.bg0};
          background-color: ${colors.yellow};
        }

        /* Tray */
        #tray {
          background-color: ${colors.bg1};
        }

        #tray > .passive {
          -gtk-icon-effect: dim;
        }

        #tray > .needs-attention {
          -gtk-icon-effect: highlight;
          background-color: ${colors.red};
          border-radius: 10px;
        }

        /* Network */
        #network {
          color: ${colors.aqua};
        }

        #network.disconnected {
          color: ${colors.red};
          background-color: ${colors.bg1};
        }

        #network:hover {
          background-color: ${colors.aqua};
          color: ${colors.bg0};
        }

        /* CPU */
        #cpu {
          color: ${colors.yellow};
        }

        #cpu:hover {
          background-color: ${colors.yellow};
          color: ${colors.bg0};
        }

        /* Memory */
        #memory {
          color: ${colors.blue};
        }

        #memory:hover {
          background-color: ${colors.blue};
          color: ${colors.bg0};
        }

        /* Disk */
        #disk {
          color: ${colors.purple};
        }

        #disk:hover {
          background-color: ${colors.purple};
          color: ${colors.bg0};
        }

        /* Bluetooth */
        #bluetooth {
          color: ${colors.blueBright};
        }

        #bluetooth:hover {
          background-color: ${colors.blueBright};
          color: ${colors.bg0};
        }

        /* Battery */
        #battery {
          color: ${colors.green};
        }

        #battery.charging,
        #battery.plugged {
          color: ${colors.greenBright};
        }

        #battery.warning:not(.charging) {
          color: ${colors.yellow};
        }

        #battery.critical:not(.charging) {
          color: ${colors.redBright};
          animation: blink 1s linear infinite alternate;
        }

        #battery:hover {
          background-color: ${colors.green};
          color: ${colors.bg0};
        }

        /* Clock */
        #clock {
          color: ${colors.fg};
          font-weight: bold;
          background-color: ${colors.bg2};
        }

        #clock:hover {
          background-color: ${colors.fg};
          color: ${colors.bg0};
        }

        /* Blink animation for critical states */
        @keyframes blink {
          to {
            background-color: ${colors.redBright};
          }
        }
      '';
    };
  };
}
