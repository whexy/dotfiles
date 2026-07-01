{
  lib,
  pkgs,
  darwin ? false,
  osConfig ? null,
  ...
}:
let
  # See nix/modules/home/gui/macbook-screen-density.nix for the full story. When that
  # compensation is active, GTK text-scaling-factor = 0.75 also shrinks
  # Firefox content (Firefox folds GTK font scaling into its CSS px → device
  # px conversion). Pinning layout.css.devPixelsPerPx to "2.0" forces Firefox
  # content to render at the same ratio Safari uses on the paired macOS host,
  # bypassing the GTK text-scaling-factor influence for web content.
  macbookScreen = !darwin && (osConfig.hardware.display.macbookScreen or false);
in
{
  programs.firefox = {
    enable = true;
    # On macOS, Firefox is installed via Homebrew cask (properly signed for 1Password).
    # Home Manager only manages profile configuration.
    package = if darwin then null else pkgs.firefox;
    # Pin the legacy profile path. HM 26.05 changed the default to
    # `$XDG_CONFIG_HOME/mozilla/firefox`, but existing profiles live at
    # `~/.mozilla/firefox`. Keeping the legacy location avoids a forced
    # manual migration across all hosts.
    configPath = lib.mkIf (!darwin) ".mozilla/firefox";
    profiles.default = {
      userChrome = builtins.readFile ./firefox/userChrome.css;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "browser.urlbar.scotchBonnet.enableOverride" = false;
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

            # Disable tabs-in-titlebar so the macOS traffic-light indicators
            # remain in a dedicated titlebar at the top of the window. This
            # is required because userChrome.css moves the tab strip to the
            # bottom; without a separate titlebar the indicators would be
            # dragged along with the tabs.
            "browser.tabs.inTitlebar" = 0;
          }
        else
          { }
      )
      // (
        if macbookScreen then
          {
            "layout.css.devPixelsPerPx" = "2.67";
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
