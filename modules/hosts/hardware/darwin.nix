{ config, lib, ... }:
let
  cfg = config.dotfiles.hardware;
in
{
  config = lib.mkMerge [
    # Auto-hide the macOS menu bar to free the top of the screen for a status
    # bar such as SketchyBar. Modern macOS needs both keys for "always hide";
    # the change only takes effect after logout/reboot (SystemUIServer does
    # not reload it live). AppleMenuBarVisibleInFullscreen is not a declared
    # nix-darwin option, so it goes through CustomUserPreferences.
    (lib.mkIf cfg.display.autoHideMenuBar {
      system.defaults = {
        NSGlobalDomain._HIHideMenuBar = true;
        CustomUserPreferences.NSGlobalDomain.AppleMenuBarVisibleInFullscreen = false;
      };
    })

    # Without these, a Mac that boots with no keyboard or pointing device
    # opens the Bluetooth Setup Assistant and waits for one to pair.
    (lib.mkIf cfg.headless {
      system.defaults.CustomSystemPreferences."/Library/Preferences/com.apple.Bluetooth" = {
        BluetoothAutoSeekKeyboard = 0;
        BluetoothAutoSeekPointingDevice = 0;
      };
    })
  ];
}
