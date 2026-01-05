# macOS-specific system configuration
{ self, username, ... }:
{
  home-manager.users.${username} = import ../home/macos/aerospace.nix;

  system.stateVersion = 6;
  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.primaryUser = username;

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
  };

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
  };
}
