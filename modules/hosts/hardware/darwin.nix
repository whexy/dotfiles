# Darwin hardware configuration: auto-hide the macOS menu bar by default to
# free the top of the screen for a status bar such as SketchyBar. MacBook
# panels opt out via `dotfiles.hardware.display.autoHideMenuBar = false`.
# Modern macOS needs both keys for "always hide"; the change only takes
# effect after logout/reboot (SystemUIServer does not reload it live).
# AppleMenuBarVisibleInFullscreen is not a declared nix-darwin option, so it
# goes through CustomUserPreferences.
{ config, lib, ... }:
{
  config = lib.mkIf config.dotfiles.hardware.display.autoHideMenuBar {
    system.defaults = {
      NSGlobalDomain._HIHideMenuBar = true;
      CustomUserPreferences.NSGlobalDomain.AppleMenuBarVisibleInFullscreen = false;
    };
  };
}
