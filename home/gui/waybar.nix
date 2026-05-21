# Waybar status bar configuration (Linux)
{
  lib,
  pkgs,
  darwin,
  ...
}:
lib.mkIf (!darwin) (
let
  # Sink picker: list PipeWire audio sinks via wpctl, pipe through fuzzel,
  # then set the chosen one as the default. Uses node.description (the
  # human-friendly name shown in `wpctl status`) so RAOP/AirPlay sinks
  # whose node.name embeds a DHCP IP still pick correctly.
  audioPickSink = pkgs.writeShellScript "waybar-audio-pick-sink" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.wireplumber
        pkgs.fuzzel
        pkgs.gawk
        pkgs.gnused
        pkgs.coreutils
      ]
    }:$PATH

    # Parse `wpctl status`: each Sink line looks like
    #   " │  *  61. HomePod                          [vol: 1.00]"
    # We want id + description, with a marker for the current default.
    lines=$(wpctl status \
      | awk '
          /^Audio/ { in_audio = 1; next }
          /^[A-Z]/  { in_audio = 0 }
          in_audio && /Sinks:/ { in_sinks = 1; next }
          in_audio && /Sources:|Filters:|Streams:/ { in_sinks = 0 }
          in_sinks && /[0-9]+\./ {
            # strip leading box-drawing/tree chars
            sub(/^[^0-9*]*/, "")
            star = ""
            if ($1 == "*") { star = "* "; $1 = "" }
            # rejoin into "id. desc [vol: ...]"
            line = $0
            sub(/^[ \t]+/, "", line)
            # drop trailing volume bracket
            sub(/[ \t]*\[vol:[^]]*\][ \t]*$/, "", line)
            print star line
          }
        ')

    [ -n "$lines" ] || exit 0

    choice=$(printf '%s\n' "$lines" | fuzzel --dmenu --prompt 'Audio sink ❯ ')
    [ -n "$choice" ] || exit 0

    # Extract numeric id (first token after optional "* ")
    id=$(printf '%s' "$choice" | sed -E 's/^\* //; s/^([0-9]+)\..*/\1/')
    [ -n "$id" ] || exit 1

    wpctl set-default "$id"
  '';

  # Brief textual status of current default sink for the waybar tooltip.
  audioStatus = pkgs.writeShellScript "waybar-audio-status" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.wireplumber
        pkgs.gawk
        pkgs.jq
        pkgs.coreutils
      ]
    }:$PATH

    # Find the description of the * (default) Audio Sink.
    sink=$(wpctl status \
      | awk '
          /^Audio/ { in_audio = 1; next }
          /^[A-Z]/  { in_audio = 0 }
          in_audio && /Sinks:/ { in_sinks = 1; next }
          in_audio && /Sources:|Filters:|Streams:/ { in_sinks = 0 }
          in_sinks && /\*/ {
            sub(/^[^*]*\* +/, "")
            sub(/^[0-9]+\. +/, "")
            sub(/[ \t]*\[vol:[^]]*\][ \t]*$/, "")
            print
            exit
          }
        ')
    [ -n "$sink" ] || sink="(no sink)"

    # Volume of @DEFAULT_AUDIO_SINK@: "Volume: 1.00 [MUTED]"
    vol_line=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "Volume: 0.00")
    vol=$(printf '%s' "$vol_line" | awk '{ printf "%d", $2 * 100 }')
    muted=false
    case "$vol_line" in *MUTED*) muted=true ;; esac

    icon="󰕾"
    class="default"
    if [ "$muted" = true ]; then
      icon="󰖁"
      class="muted"
    elif [ "$vol" -eq 0 ]; then
      icon="󰸈"
    elif [ "$vol" -lt 34 ]; then
      icon="󰕿"
    elif [ "$vol" -lt 67 ]; then
      icon="󰖀"
    fi

    text="$icon $sink"
    tooltip="$sink — $vol%"
    [ "$muted" = true ] && tooltip="$tooltip (muted)"

    jq -nc --arg t "$text" --arg tt "$tooltip" --arg c "$class" \
      '{text: $t, tooltip: $tt, class: $c, alt: $c}'
  '';
in
{
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
          "custom/audio"
          "battery"
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

        # Audio sink picker. Shows the current default sink (PipeWire),
        # left-click opens a fuzzel chooser to switch sinks, right-click
        # opens pavucontrol for per-stream routing, scroll adjusts volume,
        # middle-click toggles mute.
        "custom/audio" = {
          exec = "${audioStatus}";
          return-type = "json";
          interval = 3;
          format = "{}";
          on-click = "${audioPickSink}";
          on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
          on-click-middle = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-scroll-up = "${pkgs.wireplumber}/bin/wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
          on-scroll-down = "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
          tooltip = true;
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
      #network,
      #cpu,
      #memory,
      #disk,
      #custom-audio,
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

      /* Audio sink picker */
      #custom-audio {
        color: #d3869b;
      }

      #custom-audio.muted {
        color: #928374;
      }

      #custom-audio:hover {
        background-color: #d3869b;
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
)
