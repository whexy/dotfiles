# Desktop Darwin system configuration (macOS settings, fonts, Homebrew)
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.desktop;
in
{
  config = lib.mkIf cfg.enable {
    system.stateVersion = 6;

    fonts.packages = [
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
    ];

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

    # Homebrew casks for apps that need to be properly signed
    homebrew = {
      enable = true;
      casks = [
        "1password"
        "alfred"
        "firefox"
        "obs"
        "snipaste"
      ];
      onActivation = {
        autoUpdate = true;
        upgrade = true;
        cleanup = "zap";
        # Homebrew 5.1+ requires explicit confirmation for `brew bundle --cleanup`.
        extraFlags = [ "--force" ];
      };
    };
  };
}
