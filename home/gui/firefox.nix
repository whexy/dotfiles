{
  pkgs,
  darwin ? false,
  osConfig ? null,
  ...
}:
let
  # See home/gui/macbook-screen-density.nix for the full story. When that
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
      )
      // (
        if macbookScreen then
          {
            # Counteract GTK text-scaling-factor = 0.75 (set by
            # macbook-screen-density.nix) for Firefox web content, so a CSS
            # pixel renders at the same physical size as on the paired macOS
            # host running Safari. Chrome (tabs, menus) still follows GTK
            # scaling, which keeps it consistent with other Linux apps on
            # this machine.
            "layout.css.devPixelsPerPx" = "2.0";
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
