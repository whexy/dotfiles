# NixOS option: hardware.monitors
# Declares physical monitor/output settings per machine.
# Hardware configs set this; home modules (e.g. niri) consume it via osConfig.
{ lib, ... }:
{
  options.hardware.monitors = lib.mkOption {
    default = [ ];
    description = ''
      List of physical monitor declarations for this machine.
      Consumed by compositor configs (niri, etc.) and any other
      tool that needs to know about attached displays.
    '';
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          connector = lib.mkOption {
            type = lib.types.str;
            description = ''
              Output connector name as reported by the compositor,
              e.g. "HDMI-A-1", "DP-1", "eDP-1".
              Run `niri msg outputs` to find the exact name.
            '';
          };

          resolution = lib.mkOption {
            default = null;
            description = "Native or desired resolution. null = compositor picks automatically.";
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  width = lib.mkOption {
                    type = lib.types.int;
                    description = "Horizontal resolution in pixels.";
                  };
                  height = lib.mkOption {
                    type = lib.types.int;
                    description = "Vertical resolution in pixels.";
                  };
                };
              }
            );
          };

          refreshRate = lib.mkOption {
            type = lib.types.nullOr lib.types.float;
            default = null;
            description = ''
              Refresh rate in Hz. Must match exactly what the compositor
              reports (e.g. 120.000, not 120). null = use highest available.
            '';
          };

          scale = lib.mkOption {
            type = lib.types.nullOr lib.types.float;
            default = null;
            description = ''
              Logical pixel scale factor (e.g. 1.5 for 150% HiDPI scaling).
              null = compositor picks automatically.
            '';
          };
        };
      }
    );
  };
}
