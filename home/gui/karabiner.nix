# Karabiner-Elements configuration (macOS)
#
# Remap CapsLock to Hyper / CapsLock, Tab to Meh / Tab via tap-hold.
# This mirrors the kanata setup on NixOS (system/gui-nixos.nix).
#
# Hyper = Ctrl+Alt+Shift+Cmd (held CapsLock)
# Meh   = Ctrl+Alt+Cmd       (held Tab)
{
  osConfig,
  ...
}:
let
  keyboards = osConfig.hardware.keyboards or [ ];
in
{
  xdg.configFile."karabiner/karabiner.json".text = builtins.toJSON {
    global = {
      show_in_menu_bar = false;
    };
    profiles = [
      {
        name = "Default";
        selected = true;
        devices = map (keyboard: {
          identifiers = {
            is_keyboard = true;
            is_pointing_device = keyboard.isPointingDevice;
            product_id = keyboard.productId;
            vendor_id = keyboard.vendorId;
          };
          ignore = false;
        }) keyboards;
        complex_modifications = {
          parameters = {
            "basic.to_if_alone_timeout_milliseconds" = 200;
            "basic.to_if_held_down_threshold_milliseconds" = 200;
          };
          rules = [
            {
              description = "CapsLock → Hyper (held) / CapsLock (tapped)";
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "caps_lock";
                    modifiers.optional = [ "any" ];
                  };
                  to = [
                    {
                      key_code = "left_shift";
                      modifiers = [
                        "left_control"
                        "left_option"
                        "left_command"
                      ];
                    }
                  ];
                  to_if_alone = [
                    { key_code = "caps_lock"; }
                  ];
                }
              ];
            }
            {
              description = "Tab → Meh (held) / Tab (tapped)";
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "tab";
                    modifiers.optional = [ "any" ];
                  };
                  to = [
                    {
                      key_code = "left_control";
                      modifiers = [
                        "left_option"
                        "left_command"
                      ];
                    }
                  ];
                  to_if_alone = [
                    { key_code = "tab"; }
                  ];
                }
              ];
            }
          ];
        };
        virtual_hid_keyboard = {
          keyboard_type_v2 = "ansi";
        };
      }
    ];
  };
}
