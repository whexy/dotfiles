# GUI Darwin system configuration
{ pkgs, ... }:
{
  system.stateVersion = 6;

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
  };

  fonts.packages = [
    (pkgs.nerd-fonts.fira-code)
    (pkgs.nerd-fonts.jetbrains-mono)
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

  # 1Password GUI
  programs._1password-gui.enable = true;

  # Homebrew casks for apps that need to be properly signed
  homebrew = {
    enable = true;
    casks = [
      "alfred"
      "firefox"
      "obs"
      "snipaste"
    ];
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };
  };
}
