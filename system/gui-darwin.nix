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
      ShowPathbar = true;
    };

    trackpad.TrackpadThreeFingerDrag = true;

    spaces.spans-displays = true;
  };

  # 1Password GUI
  programs._1password-gui.enable = true;

  # Homebrew casks for apps that need to be properly signed
  homebrew = {
    enable = true;
    casks = [
      "firefox"
    ];
    onActivation.cleanup = "zap";
  };
}
