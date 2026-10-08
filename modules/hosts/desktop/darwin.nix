# Desktop Darwin system configuration: macOS desktop settings (dock, finder,
# trackpad, keyboard repeat, locale units).
{ config, lib, ... }:
let
  cfg = config.dotfiles.desktop;
in
{
  config = lib.mkIf cfg.enable {
    system.defaults = {
      menuExtraClock.Show24Hour = true;
      dock = {
        autohide = true;
        mru-spaces = false;
        show-process-indicators = false;
        show-recents = false;
        static-only = true;
      };
      finder = {
        AppleShowAllExtensions = true;
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv";
        FXDefaultSearchScope = "SCcf";
        ShowPathbar = true;
        _FXSortFoldersFirst = true;
        _FXSortFoldersFirstOnDesktop = true;
      };
      CustomUserPreferences = {
        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
      };
      NSGlobalDomain = {
        ApplePressAndHoldEnabled = false;
        KeyRepeat = 2;
        InitialKeyRepeat = 15;
        AppleTemperatureUnit = "Celsius";
        AppleMeasurementUnits = "Centimeters";
        AppleMetricUnits = 1;
      };
      spaces.spans-displays = false;
      trackpad.TrackpadThreeFingerDrag = true;
    };

    # macOS desktop utilities via Homebrew casks (need proper signatures):
    # Alfred (launcher) and Snipaste (screenshots).
    homebrew.casks = [
      "alfred"
      "snipaste"
    ];
  };
}
