args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.browser;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;

  # Platform-independent policies/settings/search engines, also consumed by
  # nix/packages/firefox-windows-profile to configure Windows Firefox.
  shared = import ./firefox/shared.nix;
in
{
  config = lib.mkIf cfg.firefox.enable (
    let
      # See nix/modules/home/desktop/macbook-screen-density.nix for the full story. When that
      # compensation is active, GTK text-scaling-factor = 0.75 also shrinks
      # Firefox content (Firefox folds GTK font scaling into its CSS px → device
      # px conversion). Pinning layout.css.devPixelsPerPx to "2.0" forces Firefox
      # content to render at the same ratio Safari uses on the paired macOS host,
      # bypassing the GTK text-scaling-factor influence for web content.
      macbookScreen = !isDarwin && (osConfig.dotfiles.hardware.display.macbookScreen or false);
    in
    {
      programs.firefox = {
        enable = true;
        # On macOS, Firefox is installed via Homebrew cask (properly signed for 1Password).
        # Home Manager only manages profile configuration.
        package = if isDarwin then null else pkgs.firefox;
        # Pin the legacy profile path. HM 26.05 changed the default to
        # `$XDG_CONFIG_HOME/mozilla/firefox`, but existing profiles live at
        # `~/.mozilla/firefox`. Keeping the legacy location avoids a forced
        # manual migration across all hosts.
        configPath = lib.mkIf (!isDarwin) ".mozilla/firefox";

        # HM's default darwinDefaultsId is "org.mozilla.firefox.plist", but
        # `defaults import` treats a domain ending in .plist as a relative file
        # path, so policies would silently never reach Firefox. Use the real
        # bundle-id defaults domain instead (only takes effect on Darwin).
        darwinDefaultsId = "org.mozilla.firefox";

        # On Linux these land in the wrapped package's policies.json; on Darwin
        # they are written to the org.mozilla.firefox defaults domain, which the
        # Homebrew-installed Firefox reads.
        inherit (shared) policies;

        profiles.default = {
          userChrome = builtins.readFile shared.userChrome;
          settings =
            shared.settings
            // (
              if isDarwin then
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

          search = {
            force = true;
            inherit (shared.search) default;
            privateDefault = shared.search.default;
            engines = lib.mapAttrs (_: engine: {
              urls = [
                { template = engine.url; }
              ]
              ++ lib.optional (engine ? suggestUrl) {
                template = engine.suggestUrl;
                type = "application/x-suggestions+json";
              };
            }) shared.search.engines;
          };
        };
      };
    }
  );
}
