# Darwin hardware configuration: hide the menu bar on machines without a
# MacBook panel (external-monitor desktop setups).
# Modern macOS needs both keys for "always hide"; the change only takes
# effect after logout/reboot (SystemUIServer does not reload it live).
# AppleMenuBarVisibleInFullscreen is not a declared nix-darwin option, so it
# goes through CustomUserPreferences.
{ config, lib, ... }:
{
  config = lib.mkIf (!config.dotfiles.hardware.display.macbookScreen) {
    system.defaults = {
      NSGlobalDomain._HIHideMenuBar = true;
      CustomUserPreferences.NSGlobalDomain.AppleMenuBarVisibleInFullscreen = false;
    };
  };
}
