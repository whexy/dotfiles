{ lib, ... }:
{
  options.hardware.keyboards = lib.mkOption {
    default = [ ];
    description = ''
      List of physical keyboard declarations for this machine.
      Consumed by tools that need stable vendor/product identifiers,
      such as Karabiner-Elements device selection.
    '';
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          vendorId = lib.mkOption {
            type = lib.types.int;
            description = "USB or Bluetooth vendor ID reported by the operating system.";
          };

          productId = lib.mkOption {
            type = lib.types.int;
            description = "USB or Bluetooth product ID reported by the operating system.";
          };

          isPointingDevice = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether the device should be identified as a pointing device in addition to a keyboard.";
          };

          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Optional human-readable name for the keyboard.";
          };
        };
      }
    );
  };
}
