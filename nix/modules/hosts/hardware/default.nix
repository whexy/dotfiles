# Hardware metadata shared by system and Home Manager modules.
# These are descriptive dotfiles options, not NixOS's hardware drivers.
{ lib, ... }:
{
  options.dotfiles.hardware = {
    display.macbookScreen = lib.mkEnableOption ''
      this machine is using a MacBook Retina panel. Linux home modules use
      this to compensate for the 72-DPI macOS versus 96-DPI GTK baseline
    '';

    keyboards = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            vendorId = lib.mkOption {
              type = lib.types.int;
              description = "USB or Bluetooth vendor ID.";
            };
            productId = lib.mkOption {
              type = lib.types.int;
              description = "USB or Bluetooth product ID.";
            };
            isPointingDevice = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether the device is also a pointing device.";
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Optional human-readable device name.";
            };
          };
        }
      );
      default = [ ];
      description = "Physical keyboards consumed by tools such as Karabiner.";
    };

    monitors = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            connector = lib.mkOption {
              type = lib.types.str;
              description = "Compositor output name, e.g. HDMI-A-1 or eDP-1.";
            };
            resolution = lib.mkOption {
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
              default = null;
              description = "Desired resolution; null lets the compositor choose.";
            };
            refreshRate = lib.mkOption {
              type = lib.types.nullOr lib.types.float;
              default = null;
              description = "Refresh rate in Hz; null chooses the highest available.";
            };
            scale = lib.mkOption {
              type = lib.types.nullOr lib.types.float;
              default = null;
              description = "Logical scale factor; null lets the compositor choose.";
            };
          };
        }
      );
      default = [ ];
      description = "Monitor declarations consumed by compositor configuration.";
    };
  };
}
