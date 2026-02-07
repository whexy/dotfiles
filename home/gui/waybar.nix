# Waybar status bar configuration (Linux)
{
  lib,
  darwin,
  ...
}:
lib.mkIf (!darwin) {
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 24;

        modules-left = [ "niri/workspaces" ];
        modules-center = [ ];
        modules-right = [
          "cpu"
          "memory"
          "disk"
          "clock"
        ];

        "niri/workspaces" = {
          format = "{icon}";
          format-icons = {
            active = "";
            default = "";
          };
        };

        cpu = {
          format = "cpu: {usage}%";
          interval = 5;
        };

        memory = {
          format = "mem: {used:0.1f}G/{total:0.1f}G";
          interval = 5;
        };

        disk = {
          format = "disk: {free}";
          path = "/";
          interval = 30;
        };

        clock = {
          format = "{:%Y-%m-%d %H:%M:%S}";
          interval = 1;
        };
      };
    };

    # Gruvbox-inspired styling
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", monospace;
        font-size: 12px;
      }

      window#waybar {
        background-color: #282828;
        color: #ebdbb2;
      }

      #workspaces button {
        padding: 0 5px;
        color: #928374;
        background-color: transparent;
        border: none;
      }

      #workspaces button.active {
        color: #ebdbb2;
        background-color: #458588;
      }

      #cpu, #memory, #disk, #clock {
        padding: 0 10px;
        color: #ebdbb2;
      }
    '';
  };
}
