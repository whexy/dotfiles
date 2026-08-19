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

  # Force-install an extension from addons.mozilla.org. Firefox downloads the
  # latest build itself and keeps it up to date, so no hashes to bump here.
  forceInstall = slug: {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
    installation_mode = "force_installed";
  };
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
        policies = {
          DisableAccounts = true;
          DisableFirefoxStudies = true;
          DisableTelemetry = true;

          GenerativeAI = {
            Enabled = false;
            Chatbot = false;
            SmartWindow = false;
            LinkPreviews = false;
            TabGroups = false;
            Locked = true;
          };

          FirefoxSuggest = {
            WebSuggestions = false;
            SponsoredSuggestions = false;
            ImproveSuggest = false;
            Locked = true;
          };
          SearchSuggestEnabled = false;

          # 1Password owns credentials, addresses, and payment methods.
          PasswordManagerEnabled = false;
          OfferToSaveLogins = false;
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;

          # Prefer encrypted DNS without breaking Tailscale or split DNS.
          DNSOverHTTPS = {
            Enabled = true;
            Fallback = true;
            Locked = false;
          };

          EnableTrackingProtection = {
            Value = true;
            Category = "strict";
            Locked = true;
          };
          HttpsOnlyMode = "enabled";

          # Remove identifying history while retaining logins, site state, and
          # cache for normal browsing performance.
          SanitizeOnShutdown = {
            History = true;
            FormData = true;
            Cookies = false;
            Sessions = false;
            SiteSettings = false;
            Cache = false;
            Locked = true;
          };

          FirefoxHome = {
            Search = true;
            TopSites = false;
            Highlights = false;
            Pocket = false;
            Stories = false;
            SponsoredTopSites = false;
            SponsoredPocket = false;
            SponsoredStories = false;
            Snippets = false;
            Weather = false;
            Locked = true;
          };

          Permissions = {
            Camera.BlockNewRequests = false;
            Microphone.BlockNewRequests = false;
            Location.BlockNewRequests = false;
            Notifications.BlockNewRequests = false;
            Autoplay.Default = "block-audio";
          };

          ExtensionSettings = {
            # uBlacklist
            "@ublacklist" = forceInstall "ublacklist";
            # AdGuard AdBlocker
            "adguardadblocker@adguard.com" = forceInstall "adguard-adblocker";
            # AdGuard VPN
            "adguard-vpn@adguard.com" = forceInstall "adguard-vpn";
            # Firenvim (also needs `:call firenvim#install(0)` on the Neovim side)
            "firenvim@lacamb.re" = forceInstall "firenvim";
            # Tampermonkey
            "firefox@tampermonkey.net" = forceInstall "tampermonkey";
            # uBlock Origin
            "uBlock0@raymondhill.net" = forceInstall "ublock-origin";
            # Vimium
            "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = forceInstall "vimium-ff";
            # 1Password
            "{d634138d-c276-4fc8-924b-40a0ea21d284}" = forceInstall "1password-x-password-manager";
          };
        };
        profiles.default = {
          userChrome = builtins.readFile ./firefox/userChrome.css;
          settings = {
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "browser.urlbar.scotchBonnet.enableOverride" = false;

            # Never restore the previous session, including after a crash.
            "browser.startup.page" = 1;
            "browser.sessionstore.resume_from_crash" = false;

            # Keep crash diagnostics local unless explicitly submitted.
            "browser.crashReports.unsubmittedCheck.enabled" = false;
            "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;
            "browser.tabs.crashReporting.sendReport" = false;
          }
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
        };

        profiles.default.search = {
          force = true;
          default = "Unduck";
          privateDefault = "Unduck";

          engines = {
            "Unduck" = {
              urls = [
                # Actual search
                {
                  template = "https://flashbang.tech";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }

                # Search suggestions
                {
                  template = "https://flashbang.tech/suggest";
                  type = "application/x-suggestions+json";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                    {
                      name = "sp";
                      value = "google";
                    }
                  ];
                }
              ];
            };
          };
        };

      };
    }
  );
}
