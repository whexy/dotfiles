{
  pkgs,
  darwin ? false,
  ...
}:
{
  programs.firefox = {
    enable = true;
    # On macOS, Firefox is installed via Homebrew cask (properly signed for 1Password).
    # Home Manager only manages profile configuration.
    package = if darwin then null else pkgs.firefox;
    profiles.default = {
      # On macOS, the bottom address bar customization would block AeroSpace.
      # We ignore it but to enable vertical tabs.
      userChrome = if darwin then "" else builtins.readFile ./firefox/userChrome.css;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      }
      // (
        if darwin then
          {
            # Recommend by Aerospace
            # see: https://nikitabobko.github.io/AeroSpace/goodies
            #
            # Disable macOS native fullscreen in Firefox
            # Disable fullscreen transition animations
            "full-screen-api.macos-native-full-screen" = false;
            "full-screen-api.transition-duration.enter" = "0 0";
            "full-screen-api.transition-duration.leave" = "0 0";

            # Firefox's vertical tabs live behind the sidebar revamp prefs.
            "sidebar.revamp" = true;
            "sidebar.verticalTabs" = true;
          }
        else
          { }
      );
    };
    profiles.default.search = {
      force = true;
      default = "Unduck";
      privateDefault = "Unduck";

      engines = {
        "Unduck" = {
          urls = [
            {
              template = "https://s.dunkirk.sh";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
        };
      };
    };
  };
}
